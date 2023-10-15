module AppBundler

using Infiltrator

import Pkg
import Pkg.BinaryPlatforms: Linux, Windows, MacOS
import Base.BinaryPlatforms: AbstractPlatform, Platform, os, arch


import Mustache
import Downloads
import Artifacts

using Tar
using CodecZlib


function extract_tar_gz(archive_path::String)

    open(archive_path, "r") do io
        decompressed = GzipDecompressorStream(io)
        return Tar.extract(decompressed)
    end
end

# packages need to be from seperate directory

julia_tarballs() = tempdir() * "/julia-tarballs/"
artifacts_cache() = tempdir() * "/artifacts/"


function retrieve_packages(app_dir, packages_dir)

    app_name = basename(app_dir)
    OLD_PROJECT = Base.active_project()

    try
        #ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0 # Just for convinience in situations where the 
        Pkg.activate(app_dir)
        Pkg.instantiate()

        for (uuid, pkginfo) in Pkg.dependencies()
            if !(uuid in keys(Pkg.Types.stdlibs()))
                cp(pkginfo.source, joinpath(packages_dir, pkginfo.name))
            end
        end

    finally
        Pkg.activate(OLD_PROJECT)
    end

end

# If one wishes he can specify artifacts_cache directory to be that in DEPOT_PATH 
# That way avoiding multiple downloads when it is deployed as a build script
function retrieve_artifacts(platform::AbstractPlatform, modules_dir, artifacts_dir; artifacts_cache_dir = artifacts_cache())

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


function retrieve_julia(platform::AbstractPlatform, julia_dir; version::VersionNumber = VERSION) # a host platform also planned here

    base_url = "https://julialang-s3.julialang.org/bin"

    url = julia_download_url(platform, version)
    isdir(julia_tarballs()) || mkdir(julia_tarballs())
        
    tarball = joinpath(julia_tarballs(), basename(url))

    if !isfile(tarball) # Hashing would be much better here
        download("$base_url/$url", tarball)
    end

    # TODO: windows needs extracting from ZIP
    source = extract_tar_gz(tarball)
    mv(joinpath(source, "julia-$version"), joinpath(julia_dir, "julia"))
    
    return nothing
end


function fill_template_save(source, dest; kwargs...)

    template = Mustache.load(joinpath(dirname(@__DIR__), "templates", source))
    output = template(; kwargs...)

    open(dest, "w") do file
        write(file, output)
    end

    return nothing
end


function copy_app(source, destination)

    mkdir(destination)

    for i in readdir(source)

        (i == "build") && continue
        (i == "meta") && continue

        cp(joinpath(source, i), joinpath(destination, i))
    end

    return
end


function bundle_app(platform::MacOS, source, destination; version = VERSION, app_name = basename(source))

    #app_name = basename(app_dir)
    rm(joinpath(destination), recursive=true, force=true)
    mkpath(destination)

    contents = joinpath(destination, "Contents")
    mkpath(contents)
    
    mkdir(contents * "/Frameworks")
    mkdir(contents * "/Resources")
    mkdir(contents * "/MacOS")

    mkdir(contents * "/Frameworks/packages")
    retrieve_packages(source, contents * "/Frameworks/packages")

    mkdir(contents * "/Frameworks/artifacts")
    retrieve_artifacts(platform, contents * "/Frameworks/packages", contents * "/Frameworks/artifacts")
    
    retrieve_julia(platform, contents * "/Frameworks"; version)

    cp(joinpath(source, "meta", "icon.icns"), joinpath(contents, "Resources", "icon.icns"))
    cp(joinpath(source, "meta", "init.jl"), joinpath(contents, "Frameworks", "init.jl"))
    cp(joinpath(source, "meta", "configure.jl"), joinpath(contents, "Frameworks", "configure.jl"))


    fill_template_save("macos/MAIN_BASH", joinpath(contents, "MacOS", app_name); APP_NAME = app_name)
    chmod(joinpath(contents, "MacOS", app_name), 0o755)

    copy_app(source, joinpath(contents, "Frameworks", app_name))

    APP_NAME = app_name
    BUILD_NUMBER = 1
    BUNDLE_IDENTIFIER = "com.example." * lowercase(APP_NAME)

    fill_template_save("macos/Info.plist", joinpath(contents, "Info.plist"); BUILD_NUMBER, BUNDLE_IDENTIFIER, APP_NAME)

    return nothing
end


function bundle_app(platform::Linux, source, destination; version = VERSION, app_name = basename(source), debug = false)

    # bundle_dir

    #bundle_name = basename(destination)

    #app_dir = joinpath(bundle_dir, app_name)
    app_dir = joinpath(tempdir(), app_name)
    rm(app_dir, recursive=true, force=true)

    mkpath(app_dir)
    mkdir(joinpath(app_dir, "bin"))
    mkdir(joinpath(app_dir, "meta"))
    mkdir(joinpath(app_dir, "lib"))
    

    mkdir(joinpath(app_dir, "lib", "packages"))
    retrieve_packages(source, joinpath(app_dir, "lib", "packages"))

    mkdir(joinpath(app_dir, "lib", "artifacts"))
    retrieve_artifacts(platform, joinpath(app_dir, "lib", "packages"), joinpath(app_dir, "lib", "artifacts"))

    retrieve_julia(platform, joinpath(app_dir, "lib"); version)

    cp(joinpath(source, "meta", "icon.png"), joinpath(app_dir, "meta", "icon.png"))
    cp(joinpath(source, "meta", "init.jl"), joinpath(app_dir, "meta", "init.jl"))
    cp(joinpath(source, "meta", "configure.jl"), joinpath(app_dir, "meta", "configure.jl"))

    
    fill_template_save("linux/main", joinpath(app_dir, "bin", app_name); APP_NAME = app_name)
    chmod(joinpath(app_dir, "bin", app_name), 0o755)

    copy_app(source, joinpath(app_dir, "lib", app_name))

    # Now I need to fill in a .desktop and the snap.yml file.
    
    mkdir(joinpath(app_dir, "meta", "gui"))
    fill_template_save("linux/main.desktop", joinpath(app_dir, "meta", "gui", "$app_name.desktop"); APP_NAME = app_name)

    fill_template_save("linux/snap.yaml", joinpath(app_dir, "meta", "snap.yaml"); APP_NAME = app_name)

    mkdir(joinpath(app_dir, "meta", "hooks"))
    fill_template_save("linux/configure", joinpath(app_dir, "meta", "hooks", "configure"); APP_NAME = app_name)
    chmod(joinpath(app_dir, "meta", "hooks", "configure"), 0o755)


    if debug
        mv(app_dir, destination)
    else
        squash_snap(app_dir, destination)
    end

    return
end

import squashfs_tools_jll


function squash_snap(source, destination)
    
    if squashfs_tools_jll.is_available()    
        mksquashfs = squashfs_tools_jll.mksquashfs()
    else
        @info "squashfs-tools not available from jll. Attempting to use mksquashfs from the system."
        mksquashfs = "mksquashfs"
    end

    run(`$mksquashfs $source $destination -noappend -comp xz`)

    return
end




bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

end
