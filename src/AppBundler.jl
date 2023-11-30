module AppBundler

# using Infiltrator
import Pkg.BinaryPlatforms: Linux, Windows, MacOS
using Scratch

DOWNLOAD_CACHE = ""

function __init__()
    global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
end

julia_tarballs() = DOWNLOAD_CACHE * "/julia-tarballs/"
artifacts_cache() = DOWNLOAD_CACHE * "/artifacts/"

include("utils.jl")
include("deps.jl")
include("bundler.jl")
include("recepies.jl")

bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

end
