module Stage

using ..AppBundler: julia_tarballs, artifacts_cache

import Downloads
import Artifacts

import Pkg
import Base.BinaryPlatforms: AbstractPlatform, Platform, os, arch, wordsize
import Pkg.BinaryPlatforms: MacOS, Linux, Windows

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

include("packages.jl")

function retrieve_packages(app_dir, packages_dir; julia_cmd=nothing)

    if isnothing(julia_cmd)

        OLD_PROJECT = Base.active_project()

        try
            ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0

            #Pkg.activate(app_dir)
            Base.ACTIVE_PROJECT[] = app_dir
            Pkg.instantiate()
            
            retrieve_packages(packages_dir)

        finally
            #Pkg.activate(OLD_PROJECT)
            Base.ACTIVE_PROJECT[] = OLD_PROJECT
            ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 1
        end

    else
        packages_src = joinpath(pkgdir(parentmodule(@__MODULE__)), "src/Utils/packages.jl")

        withenv("JULIA_PROJECT" => app_dir, "JULIA_PKG_PRECOMPILE_AUTO" => 0) do
            run(`$julia_cmd --startup-file=no --eval $("""
                import Pkg
                Pkg.instantiate()
                include(raw"$packages_src")
                retrieve_packages(raw"$packages_dir")
            """)`)
        end
    end

    return
end

# If one wishes he can specify artifacts_cache directory to be that in DEPOT_PATH 
# That way one could avoid downloading twice when it is deployed as a build script
function retrieve_artifacts(platform::AbstractPlatform, modules_dir, artifacts_dir; artifacts_cache_dir = artifacts_cache(), skip_packages = [])

    if !haskey(platform, "julia_version")
        platform = deepcopy(platform)
        platform["julia_version"] = join([VERSION.major, VERSION.minor, VERSION.patch], ".")
    end

    mkdir(artifacts_dir)

    try

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache_dir

        for dir in readdir(modules_dir)

            if dir in skip_packages
                continue
            end

            artifacts_toml = joinpath(modules_dir, dir, "Artifacts.toml")

            if isfile(artifacts_toml)
                artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)
                
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
            #return Symbol(project_dict["name"])
            return project_dict["name"]
        end
    end

    return nothing
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
    precompile::Bool = true
    incremental::Bool = true
    julia_version::VersionNumber = get_julia_version(source)
    target_instantiation::Bool = VERSION.minor != julia_version.minor
    use_stdlib_dir::Bool = true
    precompiled_modules::Vector{Symbol} = precompile ? get_project_deps(source) : []
end

PkgImage(source; kwargs...) = PkgImage(; source, kwargs...)

function override_startup_file(source, destination; module_name="")

    user_startup_file = joinpath(source, "meta/startup.jl")
    if isfile(user_startup_file)
        startup_file = user_startup_file
    else
        startup_file = joinpath(dirname(dirname(@__DIR__)), "recipes/startup.jl")
    end
    #cp(startup_file, destination, force=true)
    install(startup_file, destination; force=true, parameters = Dict("MODULE_NAME"=>module_name))
    #install(startup_file, destination; force=true, parameters)

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
function stage(product::PkgImage, platform::AbstractPlatform, destination::String)

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

    skip_packages = isdir(packages_dir) ? readdir(packages_dir) : []
    retrieve_packages(product.source, packages_dir; julia_cmd=product.target_instantiation ? "$destination/bin/julia" : nothing)

    module_name = get_module_name(product.source)
    if !isnothing(module_name)
        copy_app(product.source, joinpath(packages_dir, module_name))
    end

    override_startup_file(product.source, "$destination/etc/julia/startup.jl"; module_name) 
    apply_patches(joinpath(product.source, "meta/patches"), packages_dir; overwrite=true)
    
    @info "Retrieving artifacts"
    retrieve_artifacts(platform, packages_dir, "$destination/share/julia/artifacts"; skip_packages)

    if product.precompile
        @info "Precompiling"

        if !product.incremental
            rm("$destination/share/julia/compiled", recursive=true)
        end

        withenv("JULIA_PROJECT" => product.source, "USER_DATA" => mktempdir(), "JULIA_CPU_TARGET" => get_cpu_target(platform)) do
            julia = "$destination/bin/julia"
            run(`$julia --eval "@show LOAD_PATH; @show DEPOT_PATH; popfirst!(LOAD_PATH); popfirst!(DEPOT_PATH); import $(join(product.precompiled_modules, ','))"`)
        end

    else
        @info "Precompilation disabled. Precompilation will occur on target system at first launch."
    end

    @info "App staging completed successfully"
    @info "Staged app available at: $destination"
    @info "Launch it with bin/julia -e \"using $module_name\""

    return
end

export stage

end
