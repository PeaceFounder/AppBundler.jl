module JuliaImg

# NOTE: AppEnv coupling required for cache validity
#
# This module is tightly coupled to AppEnv due to LOAD_PATH synchronization between
# compilation and runtime. Packages with extensions require their project directory
# in LOAD_PATH during precompilation. If runtime LOAD_PATH differs from compile-time,
# Julia invalidates the cache and triggers recompilation on first use.
#
# Until extension loading can be decoupled from LOAD_PATH, AppEnv must remain
# integrated to ensure consistent LOAD_PATH across compilation and runtime.

# Need to look 
using ..AppBundler: BuildSpec
import ..AppBundler: stage, julia_tarballs, artifacts_cache

include("TerminalSpinners.jl")
include("SysImgTools.jl")

using .SysImgTools
using ..Resources
using ..Resources: get_module_name

import Base.BinaryPlatforms: AbstractPlatform, HostPlatform, os, arch#, wordsize
#import Pkg.BinaryPlatforms: MacOS, Linux, Windows
import Libdl

using UUIDs
using TOML

import Mustache
import AppEnv

function stdlib_default_dir(project)
    julia_version = get_julia_version(project)
    return "share/julia/stdlib/v$(julia_version.major).$(julia_version.minor)"
end

"""
    JuliaImgBundle(source; precompile = true, incremental = true, julia_version = get_julia_version(source))

Create a package image configuration for Julia application compilation.

This constructor initializes a JuliaImgBundle configuration that controls how a Julia application
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
pkg = JuliaImgBundle(app_dir)

# Create without precompilation (compile on target system)
pkg = JuliaImgBundle(app_dir; precompile = false)

# Create with specific Julia version and clean compilation
pkg = JuliaImgBundle(app_dir; julia_version = v"1.10.0", incremental = false)
```
"""
@kwdef struct JuliaImgBundle <: BuildSpec
    source::String
    include_lazy_artifacts::Bool = true
    stdlib_dir = stdlib_default_dir(source) # STDLIB directory relative to Sys.BINDIR

    startup_file::String = get_template(source, "startup.jl")

    sysimg_packages::Vector{String} = []
    sysimg_args::Cmd = ``
    remove_sources::Bool = false # ToDo: It only makes sense to remove sources for packages baked in the sysimg
    asset_rpath::String = "assets"
    asset_spec::Dict{Symbol, Vector{String}} = Dict{Symbol, Vector{String}}()
    precompile::Bool = true
    precompiled_modules::Vector{Symbol} = precompile ? get_project_deps(source) : []
    incremental::Bool = isempty(sysimg_packages) #true
    parallel_precompilation::Bool = (incremental || :Pkg in precompiled_modules) && !haskey(ENV, "CI")
end

function JuliaImgBundle(source; sysimg_packages = [], incremental = isempty(sysimg_packages), kwargs...) 

    if !isempty(sysimg_packages) && incremental
        @warn "All pkgimage cache needs to be rebuilt when new sysimage is built. To remove this warning set incremental=false"
        incremental = false
    end

   return JuliaImgBundle(; source, sysimg_packages, incremental, kwargs...)
end

get_julia_version(spec::JuliaImgBundle) = get_julia_version(spec.source)

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

function get_template(source, target)
    if isfile(joinpath(source, "meta", target))
        return joinpath(source, "meta", target)
    else
        path = joinpath(dirname(dirname(dirname(@__DIR__))), "recipes", target)
        isfile(path) || error("$target is not defined in recipes")
        return path
    end
end


function install(source, destination; parameters = Dict(), force = false, executable = false, predicate::Union{String, Nothing} = nothing)

    if isfile(destination) 
        if force
            rm(destination)
        else
            error("$destination already exists. Use force = true to overwrite")
        end
    else
        mkpath(dirname(destination))
    end

    total_parameters = copy(parameters)

    if !isnothing(predicate)
        total_parameters[uppercase(predicate)] = true
    end

    # Need to test that it is what I was intended
    if !isempty(total_parameters)
        template = Mustache.load(source)
        rendered = Mustache.render(template, total_parameters)
        if !isempty(strip(rendered))
            open(destination, "w") do file
                write(file, rendered)
            end
        end
    #     template = Mustache.load(source)
    #     open(destination, "w") do file
    #         Mustache.render(file, template, total_parameters)
    #     end
    else
        cp(source, destination)
    end

    if executable && Sys.isunix()
        chmod(destination, 0o755)
    end

    return
end

function configure(destination, spec; runtime_mode = "MIN", app_name = "", bundle_identifier = "")

    module_name = get_module_name(spec.source)
    stdlib_project_name = isnothing(module_name) ? "MainEnv" : module_name
    packages_dir = joinpath(destination, spec.stdlib_dir)

    if isnothing(module_name)
        envdir = joinpath(packages_dir, "MainEnv")
        mkdir(envdir)
        cp(joinpath(spec.source, "Project.toml"), joinpath(envdir, "Project.toml"))
        cp(joinpath(spec.source, "Manifest.toml"), joinpath(envdir, "Manifest.toml"))

        #module_name = "MainEnv"
    end

    # This is a part of configure because it is essential module in compilation and startup
    cp(pkgdir(AppEnv), joinpath(packages_dir, "AppEnv"); force=true)

    AppEnv.save_config(joinpath(destination, "config"); runtime_mode, stdlib_project_name, app_name, bundle_identifier)

    install(spec.startup_file, "$destination/etc/julia/startup.jl"; force=true)

    # # Here it is also possible to filter out which orgins one wants to keep
    # (; stdlib_dir) = spec
    # packages_dir = joinpath(destination, stdlib_dir)
    # pkgorigins = AppEnv.collect_pkgorigins(; root_dir = packages_dir)
    # AppEnv.save_pkgorigins(joinpath(packages_dir, "index"), pkgorigins)    

    return
end

function compile_sysimg(destination, project; 
                        sysimg_packages = [], 
                        sysimg_args = ``,
                        cpu_target = get_cpu_target(Base.BinaryPlatforms.HostPlatform()))

    julia_cmd = "$destination/bin/julia"
    #module_name = get_module_name(project)

    # Precompile packages before sysimage creation to avoid segfaults. The sysimage builder's
    # aggressive AOT compilation can trigger LLVM codegen bugs on certain constant expressions
    # (e.g., matrix inversions in Colors.jl) that don't occur during regular precompilation.
    run(`$julia_cmd --startup-file=no --pkgimages=no --project=$project --eval "import Pkg; Pkg.precompile( $(repr(string.(sysimg_packages))) )"`)

    base_sysimg = "$destination/lib/julia/sys" * ".$(Libdl.dlext)"
    tmp_sysimg = tempname() * ".$(Libdl.dlext)"

    compilation_script = sysimg_compilation_script(project, sysimg_packages)

    SysImgTools.compile_sysimage(compilation_script, tmp_sysimg; base_sysimg, julia_cmd, cpu_target, sysimg_args, project)

    mv(tmp_sysimg, base_sysimg; force=true)

    # A new SysImg invalidates precompilation cache hence we shall remove it
    rm("$destination/share/julia/compiled", recursive=true, force=true)

    return
end

function compile_pkgimgs(destination, project; 
                         precompiled_modules = [],
                         cpu_target = get_cpu_target(Base.BinaryPlatforms.HostPlatform()),
                         use_pkg = true,
                         incremental = true
                         )

    if !incremental
        rm("$destination/share/julia/compiled", recursive=true, force=true)
    end

    julia_cmd = `$destination/bin/julia --startup-file=no`
    module_name = get_module_name(project)

    stdlib_project_name = isnothing(module_name) ? "MainEnv" : module_name

    init_script = """
        empty!(LOAD_PATH)
        empty!(DEPOT_PATH)
        push!(LOAD_PATH, "@stdlib", joinpath(Sys.STDLIB, $(repr(stdlib_project_name))))
        push!(DEPOT_PATH, joinpath(dirname(Sys.BINDIR), "share/julia"))
    """
    withenv("JULIA_PROJECT" => project, "USER_DATA" => mktempdir(), "JULIA_CPU_TARGET" => cpu_target) do
        if use_pkg
            run(`$julia_cmd --eval "$init_script; import AppEnv; import Pkg; Pkg.precompile( $(repr(string.(precompiled_modules))) ) "`)
        else
            run(`$julia_cmd --eval "$init_script; import AppEnv; import $(join(precompiled_modules, ','))"`)
        end
    end

    return
end


"""
    validate_cross_compilation(product::JuliaImgBundle, platform::AbstractPlatform) -> Bool

Validate whether cross-compilation is supported for the given platform combination.
Throws descriptive errors for unsupported combinations.

# Arguments
- `product::JuliaImgBundle`: The package configuration
- `platform::AbstractPlatform`: Target platform

# Returns
- `Bool`: true if compilation is supported

# Throws
- `ArgumentError`: If cross-compilation is not supported
"""
function validate_cross_compilation(platform::AbstractPlatform)
    
    # Windows compilation
    if os(platform) == "windows" # isa Windows
        if !Sys.iswindows()
            throw(ArgumentError("Cross-compilation to Windows from $(Sys.KERNEL) is not supported"))
        end
        return true
    elseif os(platform) == "macos"
        if !Sys.isapple()
            throw(ArgumentError("Cross-compilation to macOS from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on macOS
        if Sys.ARCH == :x86_64 && arch(platform) == "aarch64"
            throw(ArgumentError("Cannot compile aarch64 binaries from x86_64 macOS"))
        end
        return true
    elseif os(platform) == "linux"
        if !Sys.islinux()
            throw(ArgumentError("Cross-compilation to Linux from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on Linux
        if Sys.ARCH !== Symbol(arch(platform))
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
function get_cpu_target(arch)
    arch === :i686        ?  "pentium4;sandybridge,-xsaveopt,clone_all"                        :
    arch === :x86_64      ?  "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"  :
    arch === :arm         ?  "armv7-a;armv7-a,neon;armv7-a,neon,vfp4"                          :
    arch === :aarch64     ?  "generic"   #= is this really the best here? =#                   :
    arch === :powerpc64le ?  "pwr8"                                                            :
        "generic"
end

get_cpu_target(platform::AbstractPlatform) = get_cpu_target(arch(platform))

function sysimg_compilation_script(project, packages)
    if isempty(packages)
        return ""
    else
        return """
            @eval Module() begin
                push!(LOAD_PATH, $(repr(pkgdir(AppEnv))))
                import AppEnv
                import $(join(packages, ','))
            end
        """
    end
end

function remove_jl_sources!(dir)
    for (root, dirs, files) in walkdir(dir; topdown=false)
        # Remove all .jl files
        for file in files
            if endswith(file, ".jl")
                filepath = joinpath(root, file)
                rm(filepath)
            end
        end
        
        # Remove directory if empty (skip the top-level dir)
        if root != dir && isempty(readdir(root))
            rm(root)
        end
    end
    
    # Needed for package loading
    cp(joinpath(pkgdir(AppEnv), "Project.toml"), joinpath(dir, "Project.toml"))

    return
end


"""
    stage(product::JuliaImgBundle, platform::AbstractPlatform, destination::String)

Stage a Julia application by downloading Julia runtime, copying packages, and optionally precompiling.

This function performs the complete staging process for a Julia application, preparing it for
distribution on the target platform. The process includes downloading the appropriate Julia runtime,
copying application dependencies, retrieving artifacts, configuring startup files, and optionally
precompiling the application.

# Arguments
- `product::JuliaImgBundle`: Package image configuration specifying source, precompilation settings, and Julia version
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
pkg = JuliaImgBundle("src/")
stage(pkg, MacOS(:arm64), "build/MyApp.app/Contents/Resources/julia")

# Stage without precompilation for faster builds
pkg = JuliaImgBundle(app_dir; precompile = false)
stage(pkg, Linux(:x86_64), "build/linux_staging")

```
"""
function stage(product::JuliaImgBundle, destination::String; platform::AbstractPlatform = HostPlatform(), cpu_target = get_cpu_target(platform), runtime_mode = "MIN", app_name = "", bundle_identifier = "")

    if product.precompile
        validate_cross_compilation(platform)
    end

    (; stdlib_dir, include_lazy_artifacts, sysimg_packages, sysimg_args, precompiled_modules) = product

    println("Fetching sources for julia-$(get_julia_version(product))-$platform")
    Resources.fetch(product.source, destination; platform, stdlib_dir, include_lazy_artifacts)

    configure(destination, product; runtime_mode, app_name, bundle_identifier)

    if !isempty(product.sysimg_packages)
        println("Compiling sysimage for $(product.sysimg_packages)...")
        compile_sysimg(destination, product.source; sysimg_packages, sysimg_args, cpu_target)
    end

    if product.precompile && !isempty(product.precompiled_modules)

        println("Precompiling pkgimgs for $(product.precompiled_modules)...")
        compile_pkgimgs(destination, product.source; precompiled_modules, cpu_target, use_pkg = product.parallel_precompilation, incremental = product.incremental)

    else
        @warn "Precompilation disabled. Precompilation will occur on target system at first launch."
    end

    # remove_sources
    module_name = get_module_name(product.source)
    packages_dir = joinpath(destination, product.stdlib_dir)
    if product.remove_sources 
        rm(packages_dir; recursive = true)
        mkdir(packages_dir)
        cp(joinpath(pkgdir(AppEnv), "Project.toml"), joinpath(packages_dir, "Project.toml"))

        stdlib_project_name = isnothing(module_name) ? "MainEnv" : module_name
        mkdir(joinpath(packages_dir, stdlib_project_name))
        cp(joinpath(product.source, "Project.toml"), joinpath(packages_dir, stdlib_project_name, "Project.toml"))
    end

    if isempty(product.asset_spec)
        Resources.install_pkgorigin_index(product.source, joinpath(destination, "index"), product.stdlib_dir)
    else
        Resources.install_assets(product.source, joinpath(destination, product.asset_rpath), product.asset_spec)
        Resources.install_pkgorigin_index(product.source, joinpath(destination, "index"), product.asset_rpath)
    end

    println("App staging completed successfully")
    println("Staged app available at: $destination")
    if !isnothing(module_name)
        println("Launch it with bin/julia -m $module_name")
    else
        println("Launch it with bin/julia")
    end

    return
end

export stage

end
