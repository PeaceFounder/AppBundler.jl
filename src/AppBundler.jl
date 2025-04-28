module AppBundler

# using Infiltrator
import Pkg.BinaryPlatforms: Linux, Windows, MacOS
using Scratch

DOWNLOAD_CACHE = ""


julia_tarballs() = joinpath(DOWNLOAD_CACHE, "julia-tarballs")
artifacts_cache() = joinpath(DOWNLOAD_CACHE, "artifacts")

include("Utils/DSStore.jl")
include("Utils/DMGPack.jl")
include("Utils/SnapPack.jl")

include("utils.jl")
include("deps.jl")
include("bundler.jl")
include("recipes.jl")
include("builder.jl")
include("setup.jl")

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

end
