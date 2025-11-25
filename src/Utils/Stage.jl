module Stage

using ..AppBundler: julia_tarballs, artifacts_cache
using ..SysImgTools

import Downloads
import Artifacts

import Pkg
import Base.BinaryPlatforms: AbstractPlatform, Platform, os, arch, wordsize
import Pkg.BinaryPlatforms: MacOS, Linux, Windows
import Libdl

using UUIDs
using TOML

using Tar
using CodecZlib

import Mustache

function install(source, destination; parameters = Dict(), force = false, executable = false)

    if isfile(destination) 
        if force
            rm(destination)
        else
            error("$destination already exists. Use force = true to overwrite")
        end
    else
        mkpath(dirname(destination))
    end

    if !isempty(parameters)
        template = Mustache.load(source)

        open(destination, "w") do file
            Mustache.render(file, template, parameters)
        end
    else
        cp(source, destination)
    end

    if executable
        chmod(destination, 0o755)
    end

    return
end

function extract_tar_gz(archive_path::String)

    open(archive_path, "r") do io
        decompressed = GzipDecompressorStream(io)
        return Tar.extract(decompressed)
    end
end

# A dublicate is in utils
"""
Move directories from source to destination. 
Only recurse into directories that already exist in destination.
"""
function merge_directories(source::String, destination::String; overwrite::Bool=false)
    
    if !isdir(source)
        error("Source directory does not exist: $source")
    end
    
    # Create destination if needed
    !isdir(destination) && mkpath(destination)
    
    # Get top-level items
    for item in readdir(source)
        src_path = joinpath(source, item)
        dest_path = joinpath(destination, item)
        
        if isdir(src_path)
            # Try to move entire directory
            if !isdir(dest_path)
                # Destination doesn't exist, move whole directory
                mv(src_path, dest_path)
                #println("Moved directory: $item")
            else
                # Destination exists, recurse into it
                #println("Merging into existing directory: $item")
                merge_directories(src_path, dest_path; overwrite=overwrite)
            end
        else
            # Move file
            mv(src_path, dest_path; force=overwrite)
            #println("Moved file: $item")
        end
    end
end

function create_pkg_context(project)

    project_toml_path = Pkg.Types.projectfile_path(project; strict=true)
    if project_toml_path === nothing
        error("could not find project at $(repr(project))")
    end
    ctx = Pkg.Types.Context(env=Pkg.Types.EnvCache(project_toml_path))

    return ctx
end

function get_transitive_dependencies(ctx, packages)

    packages_sysimg = Set{Base.PkgId}()

    frontier = Set{Base.PkgId}()
    deps = ctx.env.project.deps
    for pkg in packages
        # Add all dependencies of the package
        if ctx.env.pkg !== nothing && pkg == ctx.env.pkg.name
            push!(frontier, Base.PkgId(ctx.env.pkg.uuid, pkg))
        else
            uuid = ctx.env.project.deps[pkg]
            push!(frontier, Base.PkgId(uuid, pkg))
        end
    end
    copy!(packages_sysimg, frontier)
    new_frontier = Set{Base.PkgId}()
    while !(isempty(frontier))
        for pkgid in frontier
            deps = if ctx.env.pkg !== nothing && pkgid.uuid == ctx.env.pkg.uuid
                ctx.env.project.deps
            else
                ctx.env.manifest[pkgid.uuid].deps
            end
            pkgid_deps = [Base.PkgId(uuid, name) for (name, uuid) in deps]
            for pkgid_dep in pkgid_deps
                if !(pkgid_dep in packages_sysimg) #
                    push!(packages_sysimg, pkgid_dep)
                    push!(new_frontier, pkgid_dep)
                end
            end
        end
        copy!(frontier, new_frontier)
        empty!(new_frontier)
    end

    return packages_sysimg
end

function install_project_toml(uuid, pkgentry, destination)
    # Extract information from pkginfo
    project_dict = Dict(
        "name" => pkgentry.name,
        "uuid" => string(uuid),  # or use the package UUID if you have it
        "version" => string(pkgentry.version),
        "deps" => collect(keys(pkgentry.deps))
    )

    # Convert UUIDs to strings for TOML
    exclude = ["Test"]
    deps_dict = Dict(name => string(uuid) for (name, uuid) in pkgentry.deps if name ∉ exclude)
    project_dict["deps"] = deps_dict

    # Write to Project.toml
    open(destination, "w") do io
        TOML.print(io, project_dict)
    end

    return
end

function retrieve_packages(project, packages_dir)

    ctx = create_pkg_context(project)

    # Perhaps I need to do it at a seperate depot
    Pkg.Operations.download_source(ctx)

    for (uuid, pkgentry) in ctx.env.manifest
        
        source_path = Pkg.Operations.source_path(first(DEPOT_PATH), pkgentry)

        if isnothing(source_path)
            @warn "Skipping $(pkgentry.name)"
        else
            pkg_dir = joinpath(packages_dir, pkgentry.name)

            if !isdir(pkg_dir)

                cp(source_path, pkg_dir)

                if !isfile(joinpath(pkg_dir, "Project.toml"))
                    # We need to make a Project.toml from pkginfo
                    @warn "$(pkgentry.name) uses the legacy REQUIRE format. As a courtesy to AppBundler developers, please update it to use Project.toml."
                    install_project_toml(uuid, pkgentry, joinpath(pkg_dir, "Project.toml"))
                end
            else
                @debug "$(pkgentry.name) already exists in $packages_dir"
            end
        end
    end
end

function instantiate_manifest(app_dir; julia_cmd=nothing)

    if isnothing(julia_cmd)

        OLD_PROJECT = Base.active_project()
        try 
            ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
            Base.ACTIVE_PROJECT[] = app_dir
            Pkg.instantiate()
        finally
            Base.ACTIVE_PROJECT[] = OLD_PROJECT
            ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 1
        end    
    else
        withenv("JULIA_PROJECT" => app_dir, "JULIA_PKG_PRECOMPILE_AUTO" => 0) do
            run(`$julia_cmd --startup-file=no --eval "import Pkg; Pkg.instantiate()"`)
        end
    end

    return
end

# If one wishes he can specify artifacts_cache directory to be that in DEPOT_PATH 
# That way one could avoid downloading twice when it is deployed as a build script
function retrieve_artifacts(platform::AbstractPlatform, modules_dir, artifacts_dir; artifacts_cache_dir = artifacts_cache(), include_lazy=true)

    if !haskey(platform, "julia_version")
        platform = deepcopy(platform)
        platform["julia_version"] = string(VERSION)
    end

    mkdir(artifacts_dir)

    try

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache_dir

        for dir in readdir(modules_dir)

            artifacts_toml = joinpath(modules_dir, dir, "Artifacts.toml")

            if isfile(artifacts_toml)
                artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform, include_lazy)
                
                for name in keys(artifacts)
                    hash = artifacts[name]["git-tree-sha1"]
                    Pkg.Artifacts.ensure_artifact_installed(name, artifacts[name], artifacts_toml) 
                    cp(joinpath(artifacts_cache(), hash), joinpath(artifacts_dir, hash), force=true)
                end
            end

        end

    finally
        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = nothing
    end

    return nothing
end


function julia_download_url(platform::Linux, version::VersionNumber)

    if arch(platform) == :x86_64

        folder = "linux/x64"
        archive_name = "julia-$(version)-linux-x86_64.tar.gz"

    elseif arch(platform) == :aarch64

        folder = "linux/aarch64"
        archive_name = "julia-$(version)-linux-aarch64.tar.gz"

    else
        error("Unimplemented")
    end        

    version_folder = "$(version.major).$(version.minor)"
    url = "$(folder)/$(version_folder)/$(archive_name)"
    
    return url
end

function julia_download_url(platform::MacOS, version::VersionNumber)

    if arch(platform) == :x86_64

        folder = "mac/x64"
        archive_name = "julia-$(version)-mac64.tar.gz"

    elseif arch(platform) == :aarch64

        folder = "mac/aarch64"
        archive_name = "julia-$(version)-macaarch64.tar.gz"

    else
        error("Unimplemented")
    end

    version_folder = "$(version.major).$(version.minor)"
    url = "$(folder)/$(version_folder)/$(archive_name)"
    
    return url
end

function julia_download_url(platform::Windows, version::VersionNumber)

    folder = "winnt/x$(wordsize(platform))"
    #archive_name = "julia-$(version)-win$(wordsize(platform)).zip"
    archive_name = "julia-$(version)-win$(wordsize(platform)).tar.gz"

    version_folder = "$(version.major).$(version.minor)"
    url = "$(folder)/$(version_folder)/$(archive_name)"
    
    return url
end

function retrieve_julia(platform::AbstractPlatform, julia_dir; version = julia_version(platform)) 

    base_url = "https://julialang-s3.julialang.org/bin"

    url = julia_download_url(platform, version)
    isdir(julia_tarballs()) || mkdir(julia_tarballs())
        
    tarball = joinpath(julia_tarballs(), basename(url))

    if !isfile(tarball) # Hashing would be much better here
        download("$base_url/$url", tarball)
    end

    source = extract_tar_gz(tarball)

    #mv(joinpath(source, "julia-$version"), julia_dir)
    merge_directories(joinpath(source, "julia-$version"), julia_dir)
    
    return nothing
end

"""
    get_julia_version(source::String) -> VersionNumber

Extract the Julia version from Manifest.toml if it exists, otherwise return the current Julia version.
"""
function get_julia_version(source::String)
    manifest_file = joinpath(source, "Manifest.toml")
    
    try
        manifest_dict = TOML.parsefile(manifest_file)
        return VersionNumber(manifest_dict["julia_version"])
    catch
        @info "Reading Julia from Manifest.toml failed. Using host Julia version $VERSION instead"
        return VERSION
    end
end

function get_project_deps(source::String)

    project_file = joinpath(source, "Project.toml")

    isfile(project_file) || error("$project_file does not exist")

    project_dict = TOML.parsefile(project_file)
    
    deps_list = []

    if haskey(project_dict, "name")
        if isfile(joinpath(source, "src", project_dict["name"] * ".jl"))
            push!(deps_list, Symbol(project_dict["name"]))
        end
    end

    if haskey(project_dict, "deps")
        for (name, uuid) in project_dict["deps"]
            push!(deps_list, Symbol(name))
        end
    end    

    return deps_list
end

function get_module_name(source::String)

    project_file = joinpath(source, "Project.toml")
    project_dict = TOML.parsefile(project_file)
    
    if haskey(project_dict, "name")
        if isfile(joinpath(source, "src", project_dict["name"] * ".jl"))
            return project_dict["name"]
        end
    end

    return nothing
end

function get_template(source, target)
    if isfile(joinpath(source, "meta", target))
        return joinpath(source, "meta", target)
    else
        path = joinpath(dirname(dirname(@__DIR__)), "recipes", target)
        isfile(path) || error("$target is not defined in recipes")
        return path
    end
end


"""
    PkgImage(source; precompile = true, incremental = true, julia_version = get_julia_version(source))

Create a package image configuration for Julia application compilation.

This constructor initializes a PkgImage configuration that controls how a Julia application
is compiled and packaged, including precompilation settings and target Julia version.

# Arguments
- `source::String`: Path to the application source directory containing Project.toml and Manifest.toml

# Keyword Arguments
- `precompile = true`: If `true`, precompile the application during staging. If `false`, precompilation 
  will occur on the target system at first launch
- `incremental = true`: If `true`, use incremental compilation (faster). If `false`, perform clean 
  compilation by removing existing compiled artifacts
- `julia_version = get_julia_version(source)`: Target Julia version for the application. Defaults to 
  the version specified in Manifest.toml, or current Julia version if not found

# Examples
```julia
# Create package image with default settings
pkg = PkgImage(app_dir)

# Create without precompilation (compile on target system)
pkg = PkgImage(app_dir; precompile = false)

# Create with specific Julia version and clean compilation
pkg = PkgImage(app_dir; julia_version = v"1.10.0", incremental = false)
```
"""
@kwdef struct PkgImage
    source::String
    julia_version::VersionNumber = get_julia_version(source)
    target_instantiation::Bool = VERSION.minor != julia_version.minor
    use_stdlib_dir::Bool = true
    include_lazy_artifacts::Bool = true

    startup_file::String = get_template(source, "startup.jl")
    startup_common::String = get_template(source, "common.jl")

    sysimg_packages::Vector{String} = []
    sysimg_args::Cmd = ``

    precompile::Bool = true
    precompiled_modules::Vector{Symbol} = precompile ? get_project_deps(source) : []
    incremental::Bool = isempty(sysimg_packages) #true
    parallel_precompilation::Bool = (incremental || :Pkg in precompiled_modules) && !haskey(ENV, "CI")
end

PkgImage(source; kwargs...) = PkgImage(; source, kwargs...)

function override_startup_file(source, destination; module_name="")

    user_startup_file = joinpath(source, "meta/startup.jl")
    if isfile(user_startup_file)
        startup_file = user_startup_file
    else
        startup_file = joinpath(dirname(dirname(@__DIR__)), "recipes/startup.jl")
    end
    install(startup_file, destination; force=true, parameters = Dict("MODULE_NAME"=>module_name))

    return
end

"""
    validate_cross_compilation(product::PkgImage, platform::AbstractPlatform) -> Bool

Validate whether cross-compilation is supported for the given platform combination.
Throws descriptive errors for unsupported combinations.

# Arguments
- `product::PkgImage`: The package configuration
- `platform::AbstractPlatform`: Target platform

# Returns
- `Bool`: true if compilation is supported

# Throws
- `ArgumentError`: If cross-compilation is not supported
"""
function validate_cross_compilation(platform::AbstractPlatform)
    
    # Windows compilation
    if platform isa Windows
        if !Sys.iswindows()
            throw(ArgumentError("Cross-compilation to Windows from $(Sys.KERNEL) is not supported"))
        end
        return true
    end
    
    # macOS compilation
    if platform isa MacOS
        if !Sys.isapple()
            throw(ArgumentError("Cross-compilation to macOS from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on macOS
        if Sys.ARCH == :x86_64 && arch(platform) == :aarch64
            throw(ArgumentError("Cannot compile aarch64 binaries from x86_64 macOS"))
        end
        return true
    end
    
    # Linux compilation
    if platform isa Linux
        if !Sys.islinux()
            throw(ArgumentError("Cross-compilation to Linux from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on Linux
        if Sys.ARCH !== arch(platform)
            throw(ArgumentError("Cross-compilation across architectures not supported ($(Sys.ARCH) -> $(arch(platform)))"))
        end
        return true
    end
    
    throw(ArgumentError("Unsupported target platform: $(typeof(platform))"))
end

# function default_app_cpu_target()
#     Sys.ARCH === :i686        ?  "pentium4;sandybridge,-xsaveopt,clone_all"                        :
#     Sys.ARCH === :x86_64      ?  "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"  :
#     Sys.ARCH === :arm         ?  "armv7-a;armv7-a,neon;armv7-a,neon,vfp4"                          :
#     Sys.ARCH === :aarch64     ?  "generic"   #= is this really the best here? =#                   :
#     Sys.ARCH === :powerpc64le ?  "pwr8"                                                            :
#         "generic"
# end

"""
    get_cpu_target(platform::AbstractPlatform) -> String

Get the appropriate CPU target string for the given platform architecture.

# Arguments
- `platform::AbstractPlatform`: Target platform

# Returns
- `String`: CPU target specification for Julia compilation
"""
function get_cpu_target(platform::AbstractPlatform)
    target_arch = arch(platform)
    
    return if target_arch == :x86_64
        "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"
    elseif target_arch == :aarch64
        "generic;neoverse-n1;cortex-a76;apple-m1"
    else
        @warn "Unknown architecture $target_arch, using generic CPU target"
        "generic;"
    end
end

# A dublicate is in utils
"""
Move directories from source to destination. 
Only recurse into directories that already exist in destination.
"""
function apply_patches(source::String, destination::String; overwrite::Bool=false)
    
    if !isdir(source)
        return
    end
    
    # Create destination if needed
    !isdir(destination) && mkpath(destination)
    
    # Get top-level items
    for item in readdir(source)
        src_path = joinpath(source, item)
        dest_path = joinpath(destination, item)
        
        if isdir(src_path)
            # Try to move entire directory
            if !isdir(dest_path)
                # Destination doesn't exist, move whole directory
                cp(src_path, dest_path)
                println("Copied directory: $item")
            else
                # Destination exists, recurse into it
                #println("Merging into existing directory: $item")
                apply_patches(src_path, dest_path; overwrite=overwrite)
            end
        else
            # Copy file
            if isfile(dest_path)
                println("Overwriting file: $dest_path")
            else
                println("Copying file: $dest_path")
            end
            cp(src_path, dest_path; force=overwrite)
        end
    end
end


function sysimg_compilation_script(project, packages; 
                                   ctx = create_pkg_context(project))
    
    # packages_sysimg = get_transitive_dependencies(ctx, packages)

    # julia_code_buffer = IOBuffer()

    # for pkg in packages_sysimg
    #     print(julia_code_buffer, """
    #             println("\nCompiling $(pkg.name)")
    #             Base.require(Base.PkgId(Base.UUID("$(string(pkg.uuid))"), $(repr(pkg.name))))
    #             """)
    #     #println(julia_code_buffer, "import $(pkg.name)")
    # end

    # println(julia_code_buffer, """println("\nCompilation of mudules finished")""")

    # return String(take!(julia_code_buffer))

    if isempty(packages)
        return ""
    else
        return """
            @eval Module() begin
                println("Executing precompilation with modules: $(join(packages, ", "))...")
                import $(join(packages, ','))
                println("Precompilation executed successfully.")
            end
        """
    end
end

# function apply_upgradable_stdlib_patch(destination::String)

#     pkgdir = joinpath(destination, "Pkg")
#     target = joinpath(pkgdir, "src/Types.jl")

#     text = read(target, String)
#     text = replace(text, r"const FORMER_STDLIBS = \[.*?\]" => "const FORMER_STDLIBS = []")
#     text = replace(text, r"const UPGRADABLE_STDLIBS = \[.*?\]" => "const UPGRADABLE_STDLIBS = []")
    
#     write(target, text)

#     return
# end

function copy_app(source, destination)

    mkdir(destination)

    for i in readdir(source)
        if i in ["build", "meta"]
            continue
        end
        cp(joinpath(source, i), joinpath(destination, i))
    end

    return
end

"""
    stage(product::PkgImage, platform::AbstractPlatform, destination::String)

Stage a Julia application by downloading Julia runtime, copying packages, and optionally precompiling.

This function performs the complete staging process for a Julia application, preparing it for
distribution on the target platform. The process includes downloading the appropriate Julia runtime,
copying application dependencies, retrieving artifacts, configuring startup files, and optionally
precompiling the application.

# Arguments
- `product::PkgImage`: Package image configuration specifying source, precompilation settings, and Julia version
- `platform::AbstractPlatform`: Target platform (e.g., `MacOS(:arm64)`, `Windows(:x86_64)`, `Linux(:x86_64)`)
- `destination::String`: Target directory where the staged application will be created

# Staging Process

The function performs the following steps in order:
1. **Validation**: Checks cross-compilation support if precompilation is enabled
2. **Julia Runtime**: Downloads and extracts the appropriate Julia version for the target platform
3. **Dependencies**: Copies all non-stdlib packages from the application's Project.toml
4. **Application**: Copies the application source code to the packages directory
5. **Artifacts**: Downloads and installs platform-specific binary artifacts
6. **Configuration**: Sets up startup.jl with appropriate DEPOT_PATH and LOAD_PATH configuration
7. **Precompilation** (optional): Precompiles the application if `product.precompile = true`

# Cross-Compilation Limitations

- **Windows**: Can only compile on Windows systems
- **macOS**: Can only compile on macOS systems. Cannot compile arm64 binaries from x86_64 Macs
- **Linux**: Can only compile on Linux systems with matching architecture

# Examples
```julia
# Stage application for macOS arm64
pkg = PkgImage("src/")
stage(pkg, MacOS(:arm64), "build/MyApp.app/Contents/Resources/julia")

# Stage without precompilation for faster builds
pkg = PkgImage(app_dir; precompile = false)
stage(pkg, Linux(:x86_64), "build/linux_staging")

```
"""
function stage(product::PkgImage, platform::AbstractPlatform, destination::String; cpu_target = get_cpu_target(platform))

    if product.precompile
        validate_cross_compilation(platform)
    end

    if !haskey(platform, "julia_version")
        platform = deepcopy(platform)
        platform["julia_version"] = string(product.julia_version) # previously "$(v.major).$(v.minor).$(v.patch)" 
    else
        error("""
            Cannot specify `julia_version` in both the platform and PkgImage product.
            
            The Julia version is already set in the PkgImage product (version $(product.version)).
            Remove `julia_version` from the platform specification to resolve this conflict.
            
            Context: When building products, the platform represents the build system configuration.
            For artifact retrieval, Julia itself is considered part of the target system, where
            specifying the version directly in the platform is appropriate.
            """)
    end

    @info "Downloading Julia $(product.julia_version) for $platform"
    retrieve_julia(platform, "$destination"; version = product.julia_version)

    @info "Retrieving packages for Julia $(product.julia_version)"

    packages_dir = if product.use_stdlib_dir
        v = product.julia_version        
        "$destination/share/julia/stdlib/v$(v.major).$(v.minor)/"
    else
        @warn "Override the meta/startup.jl and meta/dmg/startup.jl manually to set the LOAD_PATH"
        "$destination/share/julia/packages" # may be useful when libs can be upgraded
    end

    #if !isfile(joinpath(product.source, "Manifest.toml"))
    @info "Instantiating project with $(product.julia_version)"
    instantiate_manifest(product.source; julia_cmd=product.target_instantiation ? "$destination/bin/julia" : nothing)
    #end

    @info "Retrieving Manifest.toml dependencies"
    retrieve_packages(product.source, packages_dir)

    module_name = get_module_name(product.source)
    if !isnothing(module_name)
        copy_app(product.source, joinpath(packages_dir, module_name))
    else
        envdir = joinpath(packages_dir, "MainEnv")
        mkdir(envdir)
        cp(joinpath(product.source, "Project.toml"), joinpath(envdir, "Project.toml"))
        cp(joinpath(product.source, "Manifest.toml"), joinpath(envdir, "Manifest.toml"))
    end

    install(product.startup_file, "$destination/etc/julia/startup.jl"; force=true, parameters = Dict("MODULE_NAME"=>module_name))
    install(product.startup_common, "$destination/etc/julia/common.jl"; force=true, parameters = Dict("MODULE_NAME"=>module_name))
        
    apply_patches(joinpath(product.source, "meta/patches"), packages_dir; overwrite=true)
    
    @info "Retrieving artifacts"
    retrieve_artifacts(platform, packages_dir, "$destination/share/julia/artifacts"; include_lazy = product.include_lazy_artifacts)

    if !isempty(product.sysimg_packages)

        @info "Compiling sysimage for $(product.sysimg_packages)..."

        julia_cmd = "$destination/bin/julia"

        # Precompile packages before sysimage creation to avoid segfaults. The sysimage builder's
        # aggressive AOT compilation can trigger LLVM codegen bugs on certain constant expressions
        # (e.g., matrix inversions in Colors.jl) that don't occur during regular precompilation.
        run(`$julia_cmd --startup-file=no --pkgimages=no --project=$(product.source) --eval "import Pkg; Pkg.precompile( $(repr(string.(product.sysimg_packages))) )"`)

        #ensurecompiled(product.source, product.sysimg_packages; julia_cmd)

        base_sysimg = "$destination/lib/julia/sys" * ".$(Libdl.dlext)"
        tmp_sysimg = tempname() * ".$(Libdl.dlext)"

        compilation_script = sysimg_compilation_script(product.source, product.sysimg_packages)
        SysImgTools.compile_sysimage(compilation_script, tmp_sysimg; base_sysimg, julia_cmd, cpu_target, sysimg_args = product.sysimg_args, project = product.source)
        mv(tmp_sysimg, base_sysimg; force=true)

    end

    if !product.incremental
        rm("$destination/share/julia/compiled", recursive=true)
    end

    if product.precompile && !isempty(product.precompiled_modules)
        @info "Precompiling..."
        withenv("JULIA_PROJECT" => product.source, "USER_DATA" => mktempdir(), "JULIA_CPU_TARGET" => cpu_target) do
            julia = "$destination/bin/julia"

            if product.parallel_precompilation
                run(`$julia --eval "@show LOAD_PATH; @show DEPOT_PATH; popfirst!(LOAD_PATH); popfirst!(DEPOT_PATH); import Pkg; Pkg.precompile( $(repr(string.(product.precompiled_modules))) ) "`)
            else
                run(`$julia --eval "@show LOAD_PATH; @show DEPOT_PATH; popfirst!(LOAD_PATH); popfirst!(DEPOT_PATH); import $(join(product.precompiled_modules, ','))"`)
            end
        end

    else
        @info "Precompilation disabled. Precompilation will occur on target system at first launch."
    end

    @info "App staging completed successfully"
    @info "Staged app available at: $destination"
    if !isnothing(module_name)
        @info "Launch it with bin/julia -e \"using $module_name\""
    else
        @info "Launch it with bin/julia"
    end

    return
end

export stage

end
