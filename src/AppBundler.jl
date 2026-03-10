module AppBundler

using Scratch
import Pkg.BinaryPlatforms: Linux, MacOS, Windows

DOWNLOAD_CACHE = ""

julia_tarballs() = joinpath(DOWNLOAD_CACHE, "julia-tarballs")
artifacts_cache() = joinpath(DOWNLOAD_CACHE, "artifacts")

"""
    BuildSpec

Abstract specification for building and packaging applications.

Concrete subtypes:
- [`JuliaImgBundle`](@ref): Julia application with full runtime
- [`JuliacBundle`](@ref): Standalone executable compiled with JuliaC
"""
abstract type BuildSpec end

function stage end


include("DMG/DSStore.jl")
include("DMG/HFS.jl")
include("DMG/DMGPack.jl")

include("Snap/SnapPack.jl")

include("MSIX/MSIXPack.jl")
include("MSIX/MSIXIcons.jl")
include("MSIX/WinSubsystem.jl")

# include("Utils/TerminalSpinners.jl")
# include("Utils/Resources.jl")
# include("Utils/SysImgTools.jl")
# include("Utils/Stage.jl")

include("bundlers/Resources.jl") # JuliaC needs assets and pkgorigins_index which is shared between JuliaImg and JuliaC
include("bundlers/JuliaImg/JuliaImg.jl") 
include("bundlers/JuliaC.jl")

#include("ArgParser.jl")

#import .ArgParser: parse_args
#import .Stage: stage # 
#using .Stage: merge_directories, install
using .JuliaImg: install
#using .Resources: merge_directories#, install
using .JuliaImg.Resources: merge_directories#, install

include("config.jl")

include("utils.jl")
include("bundle.jl")
include("recipes.jl") 

bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end



function (@main)(ARGS)

    config = parse_args(ARGS)

    target_arch = config[:target_arch]
    target_bundle = config[:target_bundle]
    build_dir = config[:build_dir]

    
    windowed = @load_preference("windowed", false)
    bundler = @load_preference("bundler", "juliaimg")

    overwrite_target = @load_preference("overwrite_target", false)

    compress = @load_preference("compress", false)
    
    # The `meta` directory is currently hardcoded
    #sources_dir = joinpath(Base.active_project(), @load_preference("sources_dir", ".."))
    sources_dir = joinpath(Base.active_project(), "..")

    version = get_version(sources_dir)

    # This is fine but I need to refactor constructors for DMG, MSIX, Snap to accept parameters 
    # Can be done post 1.0 release as it shall not affect behaviour just asthetics
    parameters = get_bundle_parameters(joinpath(sources_dir, "Project.toml"))
    app_name = parameters["APP_NAME"]

    target_name = "$(app_name)-$version-$(target_arch)"

    target_path = joinpath(build_dir, target_name)

    if bundler == "juliaimg"

        spec = JuliaImgBundle(sources_dir; 
                              precompile = @load_preference("juliaimg_precompile", true), 
                              incremental = @load_preference("juliaimg_incremental", false),
                              sysimg_packages = @load_preference("juliaimg_sysimg", [])
                              ) # todo: @load_preference("juliaimg_assets", nothing)

    elseif bundler == "juliac"

        spec = JuliaCBundle(sources_dir; trim = @load_preference("juliac_trim", false)) # todo: @load_preference("juliac_assets", [])

    else

        error("Got unsupported bundler type $bundler")

    end


    if :msix in target_bundle
        
        msix = MSIX(sources_dir; windowed, 
                (adhoc_signing ? (; pfx_cert=nothing) : (;))...)

        bundle(spec, msix, compressed ? "$target_path.msix" : target_path; force = overwrite_target, target_arch)
        
    elseif :dmg in target_bundle

        dmg = DMG(sources_dir; windowed, 
                  (adhoc_signing ? (; pfx_cert=nothing) : (;))...)

        bundle(spec, dmg, compressed ? "$target_path.dmg" : target_path; force = overwrite_target, target_arch)

    elseif :snap in target_bundle

        snap = Snap(sources_dir; windowed)
        
        bundle(spec, snap, compressed ? "$target_path.snap" : target_path; force = overwrite_target, target_arch)

    else

        error("Got unsupported bundle type $target_bundle")

    end


    return 0
end



export JuliaImgBundle, JuliaCBundle, DMG, MSIX, Snap, bundle, stage

end
