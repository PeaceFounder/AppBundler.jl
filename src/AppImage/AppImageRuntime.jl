module AppImageRuntime

using Downloads
using Scratch: @get_scratch!

const RUNTIME_TAG = "continuous"

"Runtime architectures published by AppImage/type2-runtime."
const RUNTIME_ARCHS = ("x86_64", "i686", "aarch64", "armhf")

# ToDo:
# - replace this with Artifacts.toml source
runtime_url(arch) = "https://github.com/AppImage/type2-runtime/releases/download/" *
                    "$(RUNTIME_TAG)/runtime-$(arch)"

"""
    host_arch() -> String

The runtime architecture matching the host, using AppImage's naming rather
than Julia's. Only meaningful for a Linux host; cross-packaging should pass
`arch` explicitly.
"""
function arch_string(a::Symbol)
    a === :x86_64  && return "x86_64"
    a === :i686    && return "i686"
    a === :aarch64 && return "aarch64"
    a === :arm     && return "armhf"
    a === :armv7l  && return "armhf"
    error("no AppImage runtime for host architecture $a; pass arch= explicitly")
end

"""
    runtime_cache() -> String

Scratch space holding downloaded runtimes between builds, keyed to this
package so `Pkg.gc()` can reclaim it and `Scratch.delete_scratch!` can clear
it. The path is resolved on each call rather than stored in a `const`, since
baking a scratch path into precompiled code is not safe.

Runtimes are re-downloaded if the space is garbage collected, so treat this
purely as a cache.
"""
runtime_cache() = @get_scratch!("runtimes")

# ---------------------------------------------------------------- runtime --


# It is not possible to use Artifacts.toml because it expects artifacts to be placed in tarballs
# The best option now is to wait for https://github.com/JuliaPackaging/Yggdrasil/pull/14695 to be merged
"""
    fetch_runtime(arch, cachedir) -> String

Download the prebuilt type-2 runtime for `arch` (cached in `cachedir`), and
check that it is an ELF carrying the AppImage magic `AI\\x02` at offset 8.
"""
function get_runtime(arch::AbstractString; cachedir::AbstractString = runtime_cache())
    arch in RUNTIME_ARCHS ||
        error("unknown runtime architecture $arch; expected one of $(join(RUNTIME_ARCHS, ", "))")

    mkpath(cachedir)
    dest = joinpath(cachedir, "runtime-$(arch)")
    if !isfile(dest) || filesize(dest) == 0
        @info "Downloading runtime-$(arch)"
        tmp = dest * ".part"
        try
            Downloads.download(runtime_url(arch), tmp)
            mv(tmp, dest; force = true)
        finally
            rm(tmp; force = true)
        end
    else
        @info "Using cached runtime-$(arch)"
    end

    # Belongs to the tests
    header = open(io -> read(io, 11), dest, "r")
    length(header) == 11 || error("runtime is truncated")
    header[1:4] == UInt8[0x7f, 0x45, 0x4c, 0x46] || error("runtime is not an ELF file")
    header[9:11] == UInt8[0x41, 0x49, 0x02] ||
        error("runtime lacks the AI\\x02 magic at offset 8")

    return dest
end

function get_runtime(arch::Symbol; cachedir::AbstractString = runtime_cache())
    return get_runtime(arch_string(arch); cachedir)
end

export get_runtime

end
