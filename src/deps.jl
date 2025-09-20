import Downloads
import Artifacts

import Pkg
import Base.BinaryPlatforms: AbstractPlatform, Platform, os, arch, wordsize
using AppBundlerUtils_jll
using UUIDs

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

        # Need to debug this more closelly
        chmod(joinpath(TEMP_ENV, "Project.toml"), 0o777)
        chmod(joinpath(TEMP_ENV, "Manifest.toml"), 0o777)
        
        symlink(joinpath(app_dir, "src"), joinpath(TEMP_ENV, "src"), dir_target=true)
        
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
        #Pkg.activate(app_dir)
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

    # BinaryBuilder used to add Pkg as dependency to JLLs. It is no longer needed
    # but to remove it the binary dependecies need to be rebuilt individully to drop it
    # For time being, we can simply pop Pkg from dependency list until majority of upstream packages
    # will be rebuilt.
    # remove_pkg_from_jll_packages(packages_dir)

    return
end


# function remove_pkg_from_jll_packages(packages_dir::String)
    
#     if !isdir(packages_dir)
#         error("Directory does not exist: $packages_dir")
#     end
    
#     modified_count = 0
    
#     # Get all subdirectories
#     for item in readdir(packages_dir)
#         item_path = joinpath(packages_dir, item)
        
#         # Skip if not a directory or doesn't end with _jll
#         if !isdir(item_path) || !endswith(item, "_jll")
#             continue
#         end
        
#         project_toml_path = joinpath(item_path, "Project.toml")
        
#         # Skip if Project.toml doesn't exist
#         if !isfile(project_toml_path)
#             println("Warning: No Project.toml found in $item")
#             continue
#         end
        
#         try
#             # Read the TOML file
#             project_data = TOML.parsefile(project_toml_path)
            
#             # Check if deps section exists and contains Pkg
#             if haskey(project_data, "deps") && haskey(project_data["deps"], "Pkg")
                
#                 @warn "$item is a JLL that depends on Pkg which is manually removed. Please update upstream."

#                 # Remove Pkg dependency
#                 delete!(project_data["deps"], "Pkg")
                
#                 # If deps section is now empty, remove it entirely
#                 if isempty(project_data["deps"])
#                     delete!(project_data, "deps")
#                 end
                
#                 # Write back to file
#                 chmod(project_toml_path, 0o644)  
#                 open(project_toml_path, "w") do io
#                     TOML.print(io, project_data)
#                 end
#                 chmod(project_toml_path, 0o444)  
                
#                 modified_count += 1
#             end
            
#         catch e
#             println("Error processing $item: $e")
#         end
#     end
    
#     println("\nCompleted. Modified $modified_count packages.")
    
#     return modified_count
# end


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

function retrieve_macos_launcher(platform::AbstractPlatform)

    artifacts_toml = joinpath(dirname(dirname(pathof(AppBundlerUtils_jll))), "Artifacts.toml")
    artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]

    try 

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache()
        
        hash = artifacts["git-tree-sha1"]
        Pkg.Artifacts.ensure_artifact_installed("AppBundlerUtils", artifacts, artifacts_toml) 

        return joinpath(artifacts_cache(), hash, "bin", "macos_launcher")
        #cp(joinpath(artifacts_cache(), hash, "bin", "macos_launcher"), destination, force=true)
        #chmod(destination, 0o755)

    finally
        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = nothing
    end

    return
end

