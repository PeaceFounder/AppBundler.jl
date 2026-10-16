#!/usr/bin/env julia
# PNG to ICNS - Julia translation of https://github.com/Muppetsg2/png-to-icns-py
# Original concept: https://github.com/BenSouchet/png-to-icns

module ICNS

using PNGFiles: PNGFiles
using ImageCore: RGBA, N0f8, Colorant
using ImageTransformations: imresize

export generate_icns, write_icns

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

"""
    square_pad(img)

Centre a non-square image on a transparent square canvas. Note Julia indexes
images as (row, col) == (height, width), the transpose of PIL's `size`.
"""
function square_pad(img::AbstractMatrix{<:Colorant})
    h, w = size(img)
    h == w && return convert(Matrix{RGBA{N0f8}}, img)

    n = max(h, w)
    out = fill(RGBA{N0f8}(0, 0, 0, 0), n, n)
    y0 = (n - h) ÷ 2
    x0 = (n - w) ÷ 2
    out[y0+1:y0+h, x0+1:x0+w] .= RGBA{N0f8}.(img)
    return out
end

function encode_png(img)::Vector{UInt8}
    buf = IOBuffer()
    PNGFiles.save(buf, img)
    return take!(buf)
end

"""
    generate_icns(png_path, output_path; resize=imresize)

`resize(img, n, n)` is pluggable so a different resampler can be swapped in.
Sizes shared by two OSTypes (32, 256, 512) are encoded once and reused.
"""
function generate_icns(png_path::AbstractString, output_path::AbstractString;
                       resize = imresize)
    img = square_pad(RGBA{N0f8}.(PNGFiles.load(png_path)))

    cache = Dict{Int,Vector{UInt8}}()
    elements = Pair{String,Vector{UInt8}}[]
    for (ostype, sz) in ICON_TYPES
        data = get!(cache, sz) do
            encode_png(resize(img, sz, sz))
        end
        push!(elements, ostype => data)
    end

    write_icns(output_path, elements)

    if isfile(output_path)
        println("✅ ICNS file created: $output_path")
    else
        println("❌ Failed to create ICNS file.")
    end
    return output_path
end

# --- CLI --------------------------------------------------------------------

function validate_image(path::AbstractString)
    if !isfile(path)
        println(stderr, "❌ ERROR: File '$path' does not exist.")
        exit(1)
    end
    if lowercase(splitext(path)[2]) != ".png"
        println(stderr, "❌ ERROR: File must be a .png")
        exit(1)
    end
end

const USAGE = """
Convert a PNG image to a macOS ICNS icon file.

  julia png_to_icns.jl -i <image.png> [-o <output-dir>]

  -i, --input       Path to PNG image (relative or absolute)
  -o, --output-dir  Output folder (defaults to current directory)
"""

function main(args = ARGS)
    image_path = nothing
    output_dir = "."

    i = firstindex(args)
    while i <= lastindex(args)
        a = args[i]
        if a in ("-i", "--input") && i < lastindex(args)
            image_path = args[i+1]; i += 2
        elseif a in ("-o", "--output-dir") && i < lastindex(args)
            output_dir = args[i+1]; i += 2
        elseif a in ("-h", "--help")
            print(USAGE); return 0
        else
            println(stderr, "❌ ERROR: unrecognised argument '$a'\n"); print(stderr, USAGE)
            exit(1)
        end
    end

    if image_path === nothing
        println(stderr, "❌ ERROR: --input is required\n"); print(stderr, USAGE)
        exit(1)
    end

    input_path = abspath(expanduser(image_path))
    output_dir = abspath(expanduser(output_dir))

    validate_image(input_path)
    mkpath(output_dir)

    base_name = splitext(basename(input_path))[1]
    output_file = joinpath(output_dir, "$base_name.icns")

    index = 2
    while ispath(output_file)
        output_file = joinpath(output_dir, "$(base_name)_$(index).icns")
        index += 1
    end

    generate_icns(input_path, output_file)
    return 0
end

end # module
