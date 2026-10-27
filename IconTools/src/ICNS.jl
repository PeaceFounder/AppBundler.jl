# PNG to ICNS - Julia translation of https://github.com/Muppetsg2/png-to-icns-py
# Original concept: https://github.com/BenSouchet/png-to-icns

module ICNS

using PNGFiles
using ..IconForge: toicon

export toicns

# --- ICNS container ---------------------------------------------------------
#
# Layout:
#   "icns" | UInt32be total_length | element*
#   element := OSType(4 bytes) | UInt32be length (incl. these 8 bytes) | data
#
# Everything here is PNG-embedded (ic07 and later accept PNG or JPEG2000
# payloads); the legacy raw/RLE types are not needed for modern macOS.

const ICON_TYPES = [
    ("icp4",   16),   # 16x16
    ("ic11",   32),   # 16x16@2x
    ("icp5",   32),   # 32x32
    ("ic12",   64),   # 32x32@2x
    ("ic07",  128),   # 128x128
    ("ic13",  256),   # 128x128@2x
    ("ic08",  256),   # 256x256
    ("ic14",  512),   # 256x256@2x
    ("ic09",  512),   # 512x512
    ("ic10", 1024),   # 512x512@2x
]

# function _write_element(io::IO, ostype::AbstractString, data::AbstractVector{UInt8})
#     ncodeunits(ostype) == 4 || throw(ArgumentError("OSType must be 4 bytes: $ostype"))
#     write(io, codeunits(ostype))
#     write(io, hton(UInt32(length(data) + 8)))
#     write(io, data)
# end

"""
    encode_icns(elements; toc = true) -> Vector{UInt8}

Encode an ICNS file from `elements`, a vector of `OSType => png_bytes` pairs,
and return its bytes. The optional `TOC ` element mirrors the 8-byte header of
every subsequent element and lets readers index the file without scanning it;
macOS reads files without one fine.
"""
function encode_icns(elements::AbstractVector{<:Pair{<:AbstractString,<:AbstractVector{UInt8}}};
                     toc::Bool = true)
    for (ostype, _) in elements
        ncodeunits(ostype) == 4 ||
            throw(ArgumentError("OSType must be 4 bytes, got $(repr(ostype))"))
    end

    tocsize = toc ? 8 + 8 * length(elements) : 0
    nbytes  = 8 + tocsize + sum(8 + length(data) for (_, data) in elements; init = 0)

    io = IOBuffer(; sizehint = nbytes)
    _write_header(io, "icns", nbytes)

    if toc
        _write_header(io, "TOC ", tocsize)
        for (ostype, data) in elements
            _write_header(io, ostype, 8 + length(data))
        end
    end

    for (ostype, data) in elements
        _write_header(io, ostype, 8 + length(data))
        write(io, data)
    end

    return take!(io)
end

_write_header(io::IO, ostype::AbstractString, len::Integer) =
    (write(io, codeunits(ostype)); write(io, hton(UInt32(len))))


function encode_png(img)::Vector{UInt8}
    buf = IOBuffer()
    PNGFiles.save(buf, img)
    return take!(buf)
end


"""
    toicns(img; toc = true) -> Vector{UInt8}

Encode `img` as a macOS `.icns` file and return its bytes:

    write("MyApp.icns", toicns(img))

Each size in `ICON_TYPES` is rendered with `toicon`; sizes shared by two
OSTypes (32, 256, 512) are encoded once and reused.
"""
function toicns(img; toc::Bool = true)
    cache = Dict{Int,Vector{UInt8}}()
    elements = [ostype => get!(() -> encode_png(toicon(img, sz)), cache, sz)
                for (ostype, sz) in ICON_TYPES]
    return encode_icns(elements; toc)
end

end # module
