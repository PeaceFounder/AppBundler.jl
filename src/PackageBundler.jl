module PackageBundler

using Infiltrator

import Pkg
import Mustache
import Downloads

using Tar
using CodecZlib


function extract_tar_gz(archive_path::String)

    open(archive_path, "r") do io
        decompressed = GzipDecompressorStream(io)
        return Tar.extract(decompressed)
    end
end

# packages need to be from seperate directory

depot_dir(APP_NAME::String) = tempdir() * "/depot-$APP_NAME/"
packages_dir(APP_NAME::String) = tempdir() * "/packages-$APP_NAME/"
julia_tarballs() = tempdir() * "/julia-tarballs/"

function retrieve_packages(app_dir, packages_dir)

    app_name = basename(app_dir)
    DEPOT_DIR = depot_dir(app_name)

    OLD_DEPOT_PATH = copy(DEPOT_PATH)
    OLD_PROJECT = Base.active_project()
    #OLD_JULIA_PKG_PRECOMPILE_AUTO = ENV["JULIA_PKG_PRECOMPILE_AUTO"]

    try 
        ENV["JULIA_PKG_PRECOMPILE_AUTO"] = 0
        push!(empty!(DEPOT_PATH), DEPOT_DIR)
        Pkg.activate(app_dir)
        Pkg.instantiate() # This would cost nothing if aplication is already installed
        # I may benefit from calling gc if the tempdir is long lasting
    finally
        Pkg.activate(OLD_PROJECT)
        #ENV["JULIA_PKG_PRECOMPILE_AUTO"] = OLD_JULIA_PKG_PRECOMPILE_AUTO
        DEPOT_PATH = OLD_DEPOT_PATH
    end

    for pkg_name in readdir(DEPOT_DIR * "/packages/")

        slug = readdir(DEPOT_DIR * "/packages/" * pkg_name)[1]
        source = joinpath(DEPOT_DIR, "packages", pkg_name, slug)
        #dest = MACOS_BUNDLE * "/Contents/Frameworks/packages/" * pkg_name
        dest = joinpath(packages_dir, pkg_name)

        cp(source, dest)
    end
    
    return nothing
end


function retrieve_artifacts(app_dir, artifacts_dir) # additional platform argument is planed
    # A dummy function for now

    app_name = basename(app_dir)
    DEPOT_DIR = depot_dir(app_name)

    cp(DEPOT_DIR * "/artifacts", artifacts_dir)

    return nothing
end


function retrieve_julia(version, julia_dir) # a host platform also planned here

    isdir(julia_tarballs()) || mkdir(julia_tarballs())
    tarball = julia_tarballs() * "julia-$version-macaarch64.tar.gz"

    if !isfile(tarball)

        major_version = join(split(version, ".")[1:2], ".")

        url = "https://julialang-s3.julialang.org/bin/mac/aarch64/$major_version/julia-$version-macaarch64.tar.gz"
        #url = "https://julialang-s3.julialang.org/bin/mac/x64/$major_version/julia-$version-mac64.tar.gz"
        download(url, tarball)

    end

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

# The API should be equivalent to that of PackageCompiler

function bundle_app_macos(app_dir, bundle_dir)

    app_name = basename(app_dir)
    mkpath(bundle_dir)

    contents = joinpath(bundle_dir, "$app_name.app", "Contents")
    rm(joinpath(bundle_dir, "$app_name.app"), recursive=true, force=true)
    mkpath(contents)
    
    mkdir(contents * "/Frameworks")
    mkdir(contents * "/Resources")
    mkdir(contents * "/MacOS")

    mkdir(contents * "/Frameworks/packages")
    retrieve_packages(app_dir, contents * "/Frameworks/packages")

    #mkdir(contents * "/Frameworks/artifacts")
    retrieve_artifacts(app_dir, contents * "/Frameworks/artifacts")
    
    #mkdir(contents * "/Frameworks/julia")
    retrieve_julia("1.9.3", contents * "/Frameworks")

    cp(joinpath(app_dir, "icon.icns"), joinpath(contents, "Resources", "icon.icns"))
    cp(joinpath(dirname(@__DIR__), "templates", "init.jl"), joinpath(contents, "Frameworks", "init.jl"))

    #cp(joinpath(dirname(@__DIR__), "templates", "MAIN_BASH"), joinpath(contents, "MacOS", app_name))
    fill_template_save("MAIN_BASH", joinpath(contents, "MacOS", app_name); APP_NAME = app_name)
    chmod(joinpath(contents, "MacOS", app_name), 0o755)

    cp(app_dir, joinpath(contents, "Frameworks", app_name))

    # Setting up Info.plst

    APP_NAME = app_name
    BUILD_NUMBER = 1
    BUNDLE_IDENTIFIER = "com.example." * lowercase(APP_NAME)

    fill_template_save("Info.plist", joinpath(contents, "Info.plist"); BUILD_NUMBER, BUNDLE_IDENTIFIER, APP_NAME)

    return nothing
end

# TODO
# make an example app with an icon
# run bundle_app_macos to see if that works and use infiltrator to step through the code
# see if the icon is respected, try to run the main script
# run the bundler on PeaceFounderGUI, test the main script and then finally double click



function clean_depot(app_dir)

    app_name = basename(app_dir)
    depot = depot_dir(app_name)

    rm(depot, force=true, recursive=true)
    
    return nothing
end


end # module PackageBundler
