import Downloads
import Artifacts

import Pkg
import Base.BinaryPlatforms: AbstractPlatform, Platform, os, arch, wordsize
using AppBundlerUtils_jll
using UUIDs

function retrieve_packages(app_dir, packages_dir; with_splash_screen=false)

    mkdir(packages_dir)

    app_name = basename(app_dir)
    OLD_PROJECT = Base.active_project()

    TEMP_ENV = joinpath(tempdir(), "temp_env")

    try

        mkdir(TEMP_ENV)
        cp(joinpath(app_dir, "Project.toml"), joinpath(TEMP_ENV, "Project.toml"), force=true)
        cp(joinpath(app_dir, "Manifest.toml"), joinpath(TEMP_ENV, "Manifest.toml"), force=true)
        symlink(joinpath(app_dir, "src"), joinpath(TEMP_ENV, "src"), dir_target=true)
        
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
        #Pkg.activate(app_dir)
        Pkg.activate(TEMP_ENV)
        Pkg.instantiate()

        if with_splash_screen
            Pkg.add(["GLFW", "GLAbstraction"]; preserve=Pkg.PRESERVE_ALL)
        end

        for (uuid, pkginfo) in Pkg.dependencies()
            if !(uuid in keys(Pkg.Types.stdlibs()))
                cp(pkginfo.source, joinpath(packages_dir, pkginfo.name))
            end
        end

    finally
        Pkg.activate(OLD_PROJECT)
        rm(TEMP_ENV, recursive=true, force=true)
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 1
    end

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
iswindows(platform::AbstractPlatform) = os(p,atform) == "windows"

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
    archive_name = "julia-$(version)-win$(wordsize(platform)).zip"

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

    source = extract(tarball)

    mv(joinpath(source, "julia-$version"), julia_dir)
    
    return nothing
end


function copy_app(source, destination)

    mkdir(destination)

    for i in readdir(source)

        (i == "build") && continue
        (i == "meta") && continue

        cp(joinpath(source, i), joinpath(destination, i))
    end

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


function retrieve_macos_launcher(platform::AbstractPlatform, destination)

    artifacts_toml = joinpath(dirname(dirname(pathof(AppBundlerUtils_jll))), "Artifacts.toml")
    artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]

    try 

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache()
        
        hash = artifacts["git-tree-sha1"]
        Pkg.Artifacts.ensure_artifact_installed("AppBundlerUtils", artifacts, artifacts_toml) 
        cp(joinpath(artifacts_cache(), hash, "bin", "macos_launcher"), destination, force=true)
        chmod(destination, 0o755)

    finally
        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = nothing
    end

    return
end
