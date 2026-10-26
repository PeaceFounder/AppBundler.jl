
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
- [`JuliaImg.JuliaImgBundle`](@ref): Julia application with full runtime
- [`JuliaC.JuliacBundle`](@ref): Standalone executable compiled with JuliaC
"""
abstract type BuildSpec end

function stage end

include("DMG/DSStore.jl")
include("DMG/HFSTools.jl")
include("DMG/HFSImg.jl")
include("DMG/DMGPack.jl")

include("Snap/SnapPack.jl")

include("AppImage/AppImageRuntime.jl")
include("AppImage/AppImagePack.jl")

include("MSIX/MSIXPack.jl")
include("MSIX/WinSubsystem.jl")
include("MSIX/MSIX2EXEPack.jl")

# JuliaC needs assets and pkgorigins_index which is shared between JuliaImg and JuliaC
include("bundlers/Resources.jl") 
include("bundlers/JuliaImg/JuliaImg.jl") 
include("bundlers/JuliaC.jl")

using .JuliaImg: install
using .JuliaImg.Resources: merge_directories


include("utils.jl")
include("bundle.jl")
include("recipes.jl") 

include("ArgTools.jl")
include("PrefTools.jl")

include("preferences.jl")

include("status.jl")
include("inline.jl")
include("main.jl")

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end


using PrecompileTools

@setup_workload begin
    project_dir = joinpath(dirname(@__DIR__), "examples", "GLApp")

    # @compile_workload begin
    #     # :color => true so the printstyled / escape-code branches get compiled too
    #     io = IOContext(IOBuffer(), :color => true)
    #     print_preferences(io, project_dir)
    #     print_overrides(io, project_dir)
        
    # end
end

export JuliaImgBundle, JuliaCBundle, DMG, MSIX, Snap, bundle, stage
export main 

end
