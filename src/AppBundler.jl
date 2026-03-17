module AppBundler

using Scratch
import Pkg.BinaryPlatforms: Linux, MacOS, Windows
import Pkg

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

include("MSIX/OpenSSLLegacy.jl")
include("MSIX/MSIXPack.jl")
include("MSIX/MSIXIcons.jl")
include("MSIX/WinSubsystem.jl")

include("bundlers/Resources.jl") # JuliaC needs assets and pkgorigins_index which is shared between JuliaImg and JuliaC
include("bundlers/JuliaImg/JuliaImg.jl") 
include("bundlers/JuliaC.jl")

using .JuliaImg: install
using .JuliaImg.Resources: merge_directories#, install

include("main.jl")
include("utils.jl")
include("bundle.jl")
include("recipes.jl") 

#bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end

export JuliaImgBundle, JuliaCBundle, DMG, MSIX, Snap, bundle, stage
export main 


end
