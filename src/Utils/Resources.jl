module Resources

using Tar
using CodecZlib
using TOML
import Pkg
import Artifacts
import Downloads

import Base.BinaryPlatforms: AbstractPlatform, arch, wordsize
import Pkg.BinaryPlatforms: MacOS, Linux, Windows

# Import from parent module
using ..AppBundler: julia_tarballs, artifacts_cache

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

function retrieve_packages(project, packages_dir)

    ctx = create_pkg_context(project)

    # Perhaps I need to do it at a seperate depot
    Pkg.Operations.download_source(ctx)

    for (uuid, pkgentry) in ctx.env.manifest
        
        #source_path = Pkg.Operations.source_path(first(DEPOT_PATH), pkgentry)
        source_path = Pkg.Operations.source_path(joinpath(project, "Manifest.toml"), pkgentry)

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

    module_name = get_module_name(project)
    if !isnothing(module_name)
        rm(joinpath(packages_dir, module_name); recursive=true, force=true)
        copy_app(project, joinpath(packages_dir, module_name))
    end

    return
end


# It would be better to refactor this module so it would go through the context object directly with the instantiated packages

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

# A dublicate is in utils
"""
Move directories from source to destination. 
Only recurse into directories that already exist in destination.
"""

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
    get_julia_version(source::String) -> VersionNumber

Extract the Julia version from Manifest.toml if it exists, otherwise return the current Julia version.
"""
function get_julia_version(source::String)
    manifest_file = joinpath(source, "Manifest.toml")

    try
        manifest_dict = TOML.parsefile(manifest_file)
        return VersionNumber(manifest_dict["julia_version"])
    catch
        error("Failing to read Julia version from Manifest.toml")
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


function fetch(project, destination; 
               platform = Base.BinaryPlatforms.HostPlatform(), # OS and arch
               include_lazy_artifacts = true,
               stdlib_dir = nothing
               )

    if !isfile(joinpath(project, "Manifest.toml"))
        instantiate_manifest(project) # Happens with host Julia version
    end

    julia_version = get_julia_version(project)
    
    if isnothing(stdlib_dir)
        stdlib_dir = "share/julia/stdlib/v$(julia_version.major).$(julia_version.minor)"
    end

    if !haskey(platform, "julia_version")
        platform = deepcopy(platform)
        platform["julia_version"] = string(julia_version) # previously "$(v.major).$(v.minor).$(v.patch)" 

    elseif VersionNumber(platform["julia_version"]) != julia_version
        
        error("""
            Different julia_version specified: platform has "$(platform["julia_version"])" 
            but Manifest.toml requires $(julia_version).

            Remove julia_version from the platform specification.
            
            Context: When building products, the platform represents the build system configuration.
            For artifact retrieval, Julia itself is considered part of the target system, where
            specifying the version directly in the platform is appropriate.
            """)
    end

    retrieve_julia(platform, destination; version = julia_version)

    packages_dir = joinpath(destination, stdlib_dir)
    retrieve_packages(project, packages_dir)

    apply_patches(joinpath(project, "meta/patches"), packages_dir; overwrite=true)

    retrieve_artifacts(platform, packages_dir, "$destination/share/julia/artifacts"; include_lazy = include_lazy_artifacts)
    
    return
end

end
