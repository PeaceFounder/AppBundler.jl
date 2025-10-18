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

function install_project_toml(uuid, pkginfo, destination)
    # Extract information from pkginfo
    project_dict = Dict(
        "name" => pkginfo.name,
        "uuid" => string(uuid),  # or use the package UUID if you have it
        "version" => string(pkginfo.version),
        "deps" => pkginfo.dependencies
    )

    # Convert UUIDs to strings for TOML
    exclude = ["Test"]
    deps_dict = Dict(name => string(uuid) for (name, uuid) in pkginfo.dependencies if name ∉ exclude)
    project_dict["deps"] = deps_dict

    # Write to Project.toml
    open(destination, "w") do io
        TOML.print(io, project_dict)
    end

    return
end

function retrieve_packages(app_dir, packages_dir; with_splash_screen=false)

    mkpath(packages_dir)

    app_name = basename(app_dir)
    OLD_PROJECT = Base.active_project()

    TEMP_ENV = mktempdir() 

    try

        cp(joinpath(app_dir, "Project.toml"), joinpath(TEMP_ENV, "Project.toml"), force=true)
        chmod(joinpath(TEMP_ENV, "Project.toml"), 0o444) # perhaps 0o444 could work as well

        if isfile(joinpath(app_dir, "Manifest.toml"))
            cp(joinpath(app_dir, "Manifest.toml"), joinpath(TEMP_ENV, "Manifest.toml"), force=true)
            chmod(joinpath(TEMP_ENV, "Manifest.toml"), 0o444)
        end

        if isfile(joinpath(app_dir, "deps/build.jl"))
            mkdir(joinpath(TEMP_ENV, "deps"))
            cp(joinpath(app_dir, "deps/build.jl"), joinpath(TEMP_ENV, "deps/build.jl"))
        end
        
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
        Pkg.activate(TEMP_ENV)
        Pkg.instantiate()

        for (uuid, pkginfo) in Pkg.dependencies()
            if !(uuid in keys(Pkg.Types.stdlibs()))

                pkg_dir = joinpath(packages_dir, pkginfo.name)

                if !isdir(pkg_dir)
                    cp(pkginfo.source, pkg_dir)
                    if !isfile(joinpath(pkg_dir, "Project.toml"))
                        # We need to make a Project.toml from pkginfo
                        @warn "$(pkginfo.name) uses the legacy REQUIRE format. As a courtesy to AppBundler developers, please update it to use Project.toml."
                        install_project_toml(uuid, pkginfo, joinpath(pkg_dir, "Project.toml"))
                    end
                else
                    @info "$(pkginfo.name) already exists in $packages_dir"
                end
            end
        end

    finally
        Pkg.activate(OLD_PROJECT)
        rm(TEMP_ENV, recursive=true, force=true)
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 1
    end

    return
end


# If one wishes he can specify artifacts_cache directory to be that in DEPOT_PATH 
# That way one could avoid downloading twice when it is deployed as a build script
function retrieve_artifacts(platform::AbstractPlatform, modules_dir, artifacts_dir; artifacts_cache_dir = artifacts_cache())

    if !haskey(platform, "julia_version")
        platform = deepcopy(platform)
        platform["julia_version"] = join([VERSION.major, VERSION.minor, VERSION.patch], ".")
    end

    mkdir(artifacts_dir)

    try

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache_dir

        for dir in readdir(modules_dir)

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


function copy_app(source, destination)

    mkdir(destination)

    for i in readdir(source)

        (i == "build") && continue
        (i == "meta") && continue

        cp(joinpath(source, i), joinpath(destination, i))
    end

    toml_dict = TOML.parsefile(joinpath(source, "Project.toml"))

    # This may be temporary
    if haskey(toml_dict, "name") && haskey(toml_dict, "uuid")
        module_name = toml_dict["name"]
    else
        #rm(joinpath(destination, "Project.toml"))

        if !haskey(toml_dict, "name")
            @warn "Name of the application not found in Project.toml"
            toml_dict["name"] = basename(destination)
        end

        if !haskey(toml_dict, "uuid")
            @info "Assigning UUID for the Project.toml"
            toml_dict["uuid"] = string(uuid4())
        end

        open(joinpath(destination, "Project.toml"), "w") do io
            TOML.print(io, toml_dict)
        end
    end
    
    module_name = toml_dict["name"]

    path = joinpath(destination, "src/$module_name.jl")

    if !isfile(path)

        mkpath(joinpath(destination, "src"))

        dependencies = toml_dict["deps"]
        deps = join(["using $i" for i in keys(dependencies)], "\n")

        write(path, """
        module $module_name
        $deps
        end
        """)

    end

    return
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
end

PkgImage(source; precompile = true, incremental = true, julia_version = get_julia_version(source)) = PkgImage(; source, precompile, incremental, julia_version)



function get_module_name(source_dir)
    
    if isfile(joinpath(source_dir), "Project.toml")
        toml_dict = TOML.parsefile(joinpath(source_dir,"Project.toml"))
        return get(toml_dict, "name", "MainEntry")
    else
        @warn "Returning source directory name as last resort for module name as Project.toml not found"
        return basename(source_dir)
    end

end

function override_startup_file(source, destination; parameters = Dict())

    user_startup_file = joinpath(source, "meta/startup.jl")
    if isfile(user_startup_file)
        startup_file = user_startup_file
    else
        startup_file = joinpath(dirname(dirname(@__DIR__)), "recipes/startup.jl")
    end
    #cp(startup_file, destination, force=true)
    install(startup_file, destination; parameters, force = true)

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


"""
    stage(product::PkgImage, platform::AbstractPlatform, destination::String; module_name = get_module_name(product.source))

Stage a Julia application by downloading Julia runtime, copying packages, and optionally precompiling.

This function performs the complete staging process for a Julia application, preparing it for
distribution on the target platform. The process includes downloading the appropriate Julia runtime,
copying application dependencies, retrieving artifacts, configuring startup files, and optionally
precompiling the application.

# Arguments
- `product::PkgImage`: Package image configuration specifying source, precompilation settings, and Julia version
- `platform::AbstractPlatform`: Target platform (e.g., `MacOS(:arm64)`, `Windows(:x86_64)`, `Linux(:x86_64)`)
- `destination::String`: Target directory where the staged application will be created

# Keyword Arguments
- `module_name = get_module_name(product.source)`: Name of the main application module. Defaults to the 
  name specified in Project.toml

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

# Stage with specific module name
stage(pkg, Windows(:x86_64), "build/windows_staging"; module_name = "MyCustomApp")
```
"""
function stage(product::PkgImage, platform::AbstractPlatform, destination::String; module_name = get_module_name(product.source))

    if product.precompile
        validate_cross_compilation(platform)
    end

    @info "Downloading Julia $(product.julia_version) for $platform"
    retrieve_julia(platform, "$destination"; version = product.julia_version)

    retrieve_packages(product.source, "$destination/share/julia/packages")
    copy_app(product.source, "$destination/share/julia/packages/$module_name")

    retrieve_artifacts(platform, "$destination/share/julia/packages", "$destination/share/julia/artifacts")

    # Perhaps the LOAD_PATH could be manipulated only for the compilation
    override_startup_file(product.source, "$destination/etc/julia/startup.jl"; parameters = Dict("MODULE_NAME" => module_name))

    if product.precompile
        @info "Precompiling"

        if !product.incremental
            rm("$destination/share/julia/compiled", recursive=true)
        end

        withenv("JULIA_PROJECT" => "$destination/share/julia/packages/$module_name", "USER_DATA" => mktempdir(), "JULIA_CPU_TARGET" => get_cpu_target(platform)) do

            julia = "$destination/bin/julia"
            run(`$julia --eval "@show LOAD_PATH; @show DEPOT_PATH; popfirst!(LOAD_PATH); popfirst!(DEPOT_PATH); import $module_name"`)
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
