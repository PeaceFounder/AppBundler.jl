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

function _write_element(io::IO, ostype::AbstractString, data::AbstractVector{UInt8})
    ncodeunits(ostype) == 4 || throw(ArgumentError("OSType must be 4 bytes: $ostype"))
    write(io, codeunits(ostype))
    write(io, hton(UInt32(length(data) + 8)))
    write(io, data)
end

"""
    write_icns(path, elements; toc=true)

Write an ICNS file from `elements`, a vector of `OSType => png_bytes` pairs.
The optional `TOC ` element mirrors the 8-byte header of every subsequent
element and lets readers index the file without scanning it; macOS reads
files without one fine.
"""
function write_icns(path::AbstractString,
                    elements::AbstractVector{<:Pair{<:AbstractString,<:AbstractVector{UInt8}}};
                    toc::Bool = true)
    body = IOBuffer()

    if toc
        tocbuf = IOBuffer()
        for (ostype, data) in elements
            write(tocbuf, codeunits(ostype))
            write(tocbuf, hton(UInt32(length(data) + 8)))
        end
        _write_element(body, "TOC ", take!(tocbuf))
    end

    for (ostype, data) in elements
        _write_element(body, ostype, data)
    end

    payload = take!(body)
    open(path, "w") do io
        write(io, codeunits("icns"))
        write(io, hton(UInt32(length(payload) + 8)))
        write(io, payload)
    end
    return path
end

# --- image handling ---------------------------------------------------------



function encode_png(img)::Vector{UInt8}
    buf = IOBuffer()
    PNGFiles.save(buf, img)
    return take!(buf)
end

"""
    toicns(png_path, output_path; resize=imresize)

`resize(img, n, n)` is pluggable so a different resampler can be swapped in.
Sizes shared by two OSTypes (32, 256, 512) are encoded once and reused.
"""
function toicns(img, output_path::AbstractString)
    #img = square_pad(RGBA{N0f8}.(PNGFiles.load(png_path)))

    cache = Dict{Int,Vector{UInt8}}()
    elements = Pair{String,Vector{UInt8}}[]
    for (ostype, sz) in ICON_TYPES
        data = get!(cache, sz) do
            #encode_png(resize(img, sz, sz))
            encode_png(toicon(img, sz))
        end
        push!(elements, ostype => data)
    end

    write_icns(output_path, elements)
    
    return
end


end # module
