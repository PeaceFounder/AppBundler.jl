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
                println("Moved directory: $item")
            else
                # Destination exists, recurse into it
                println("Merging into existing directory: $item")
                merge_directories(src_path, dest_path; overwrite=overwrite)
            end
        else
            # Move file
            mv(src_path, dest_path; force=overwrite)
            println("Moved file: $item")
        end
    end
end

function retrieve_packages(app_dir, packages_dir; with_splash_screen=false)

    #mkdir(packages_dir)
    mkpath(packages_dir)

    app_name = basename(app_dir)
    OLD_PROJECT = Base.active_project()

    TEMP_ENV = joinpath(tempdir(), "temp_env")

    try

        mkdir(TEMP_ENV)
        cp(joinpath(app_dir, "Project.toml"), joinpath(TEMP_ENV, "Project.toml"), force=true)
        cp(joinpath(app_dir, "Manifest.toml"), joinpath(TEMP_ENV, "Manifest.toml"), force=true)

        if isfile(joinpath(app_dir, "deps/build.jl"))
            mkdir(joinpath(TEMP_ENV, "deps"))
            cp(joinpath(app_dir, "deps/build.jl"), joinpath(TEMP_ENV, "deps/build.jl"))
        end

        # Need to debug this more closelly
        chmod(joinpath(TEMP_ENV, "Project.toml"), 0o444) # perhaps 0o444 could work as well
        chmod(joinpath(TEMP_ENV, "Manifest.toml"), 0o444)
        
        
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
        Pkg.activate(TEMP_ENV)
        Pkg.instantiate()

        # if with_splash_screen
        #     Pkg.add(["GLFW", "GLAbstraction"]; preserve=Pkg.PRESERVE_ALL)
        # end

        for (uuid, pkginfo) in Pkg.dependencies()
            if !(uuid in keys(Pkg.Types.stdlibs()))

                pkg_dir = joinpath(packages_dir, pkginfo.name)

                if !isdir(pkg_dir)
                    cp(pkginfo.source, pkg_dir)
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


ismacos(platform::AbstractPlatform) = os(platform) == "macos"
islinux(platform::AbstractPlatform) = os(platform) == "linux" 
iswindows(platform::AbstractPlatform) = os(platform) == "windows"

function platform_type(platform::Platform)
    if islinux(platform)

        return Linux(Symbol(arch(platform)))

    elseif ismacos(platform)

        return MacOS(Symbol(arch(platform)))

    elseif iswindows(platform)
        
        return Windows(Symbol(platform))

    else
        return platform
    end
end


function HostPlatform()

    platform = Base.BinaryPlatforms.HostPlatform()

    return platform_type(platform)
end


julia_download_url(platform::Platform, version::VersionNumber) = julia_download_url(platform_type(platform), version)


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

function julia_version(platform::AbstractPlatform)
    
    if haskey(platform, "julia_version")
        version = VersionNumber(platform["julia_version"])
    else
        version = VERSION
    end

    # if version.major == VERSION.major && version.minor == VERSION.minor && version > VERSION
    #     return VERSION
    # else
    #     return version
    # end

    return version
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

    # Remove Pkg dependency

    # rm(joinpath(destination, "Manifest.toml"))
    # # OLD_PROJECT = Base.active_project()
    # # try
    # #     ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
    # #     Pkg.activate(destination)
    # #     Pkg.resolve()
    # # finally
    # #     Pkg.activate(OLD_PROJECT)
    # #     ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 1
    # # end

    # Creating a module if it does not exists

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


@kwdef struct PkgImage
    source::String
    precompile::Bool = true
    incremental::Bool = true
    julia_version::VersionNumber = get_julia_version(source)
end

PkgImage(source; precompile = true, incremental = true, julia_version = get_julia_version(source)) = PkgImage(; source, precompile, incremental, julia_version)


get_parameters(product::PkgImage) = get_bundle_parameters("$(product.source)/Project.toml")


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


function stage(product::PkgImage, platform::AbstractPlatform, destination::String; module_name = get_module_name(product.source))

    if product.precompile
        validate_cross_compilation(platform)
    end

    #rm(destination, recursive=true, force=true)
    #mkpath(dirname(destination))

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
