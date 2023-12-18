module AppBundler

# using Infiltrator
using Scratch

const Linux = Val{:linux}
const Windows = Val{:windows}
const MacOS = Val{:macos}

DOWNLOAD_CACHE = ""

function __init__()
    global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
end

julia_tarballs() = DOWNLOAD_CACHE * "/julia-tarballs/"
artifacts_cache() = DOWNLOAD_CACHE * "/artifacts/"

include("utils.jl")
include("deps.jl")
include("bundler.jl")
include("recipes.jl")

bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

end
