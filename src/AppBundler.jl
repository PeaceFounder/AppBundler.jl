module AppBundler

using Scratch
import Pkg.BinaryPlatforms: Linux, MacOS, Windows

DOWNLOAD_CACHE = ""

julia_tarballs() = joinpath(DOWNLOAD_CACHE, "julia-tarballs")
artifacts_cache() = joinpath(DOWNLOAD_CACHE, "artifacts")

include("Utils/DSStore.jl")
include("Utils/HFS.jl")
include("Utils/DMGPack.jl")
include("Utils/SnapPack.jl")
include("Utils/MSIXPack.jl")
include("Utils/MSIXIcons.jl")
include("Utils/WinSubsystem.jl")

include("Utils/TerminalSpinners.jl")
include("Utils/SysImgTools.jl")

include("Utils/Stage.jl")
include("Utils/ArgParser.jl")

import .ArgParser: parse_args
import .Stage: stage # 
using .Stage: merge_directories, install

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

export Linux, MacOS, Windows

end
