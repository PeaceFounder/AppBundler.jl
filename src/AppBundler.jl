module AppBundler

# using Infiltrator
import Pkg.BinaryPlatforms: Linux, Windows, MacOS
using Scratch

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

include("utils.jl")
include("api.jl")
include("deps.jl")
# include("bundler.jl")
# include("recipes.jl")
#include("builder.jl")
include("setup.jl")

# Experimental API
include("stage.jl")
include("apps.jl")

bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)


import OpenSSL_jll

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 

        # fixing OpenSSL
        openssl_bin = joinpath(OpenSSL_jll.artifact_dir, "bin")
        ENV["PATH"] = openssl_bin * ";" * ENV["PATH"]
        ENV["OPENSSL_CONF"] = ""
        ENV["OPENSSL_MODULES"] = ""
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end

end
