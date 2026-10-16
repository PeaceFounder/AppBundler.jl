module SVGRenderer

import PNGFiles
import resvg_jll   # add to Project.toml: resvg_jll = "..."
using ColorTypes
using FixedPointNumbers

# CSS absolute lengths, in px at the 96 dpi reference.
const CSS_UNITS = Dict("" => 1.0, "px" => 1.0, "pt" => 96/72, "pc" => 16.0,
                       "in" => 96.0, "cm" => 96/2.54, "mm" => 96/25.4)
struct SVGImage
    data::Vector{UInt8}
    width::Float64
    height::Float64
end

# Returns nothing for percentages and unknown units, so the caller falls back
# to viewBox.
function attr_px(root, name)
    m = match(Regex("\\b$name\\s*=\\s*[\"']([^\"']+)"), root)
    m === nothing && return nothing
    n = match(r"^\s*([+-]?[\d.]+(?:[eE][+-]?\d+)?)\s*([a-z]*)\s*$", m.captures[1])
    n === nothing && return nothing
    scale = get(CSS_UNITS, n.captures[2], nothing)
    scale === nothing ? nothing : parse(Float64, n.captures[1]) * scale
end

function SVGImage(data::Vector{UInt8})
    root = match(r"<svg\b[^>]*>"s, String(@view data[1:min(end, 4096)])).match
    w, h = attr_px(root, "width"), attr_px(root, "height")
    if w === nothing || h === nothing
        vb = match(r"viewBox\s*=\s*[\"']([^\"']+)", root)
        vb === nothing && error("SVG declares no usable width/height or viewBox")
        n = parse.(Float64, split(strip(vb.captures[1]), r"[\s,]+"))
        w, h = something(w, n[3]), something(h, n[4])
    end
    return SVGImage(data, w, h)
end

Base.show(io::IO, img::SVGImage) =
    print(io, "SVGImage(", img.width, " × ", img.height, ", ", sizeof(img.data), " bytes)")


function render(svg::SVGImage, h, w)
    (h > 0 && w > 0) || throw(ArgumentError("target dimensions must be positive"))
    isapprox(w / h, svg.width / svg.height; rtol = 1 / min(h, w)) ||
        @warn "Target $(w)×$(h) does not match SVG proportions $(svg.width)×$(svg.height)"

    #@infiltrate

    cmd = `$(resvg_jll.resvg()) --resources-dir $(tempdir()) --width $w --height $h - -c`
    #cmd = `$(resvg_jll.resvg()) --width $w --height $h - -c`
    #cmd = `$(resvg_jll.resvg()) --width $w --height $h -c -`
    png = read(pipeline(cmd; stdin = IOBuffer(svg.data)))
    img = convert(Matrix{RGBA{N0f8}}, PNGFiles.load(IOBuffer(png)))

    return img
end

# function render(svg::SVGImage, dims::Tuple{Integer,Integer}; method = :auto)
#     h, w = dims
#     (h > 0 && w > 0) || throw(ArgumentError("target dimensions must be positive"))

#     cmd = `$(resvg_jll.resvg()) --width $w --height $h - -`
#     png = read(pipeline(cmd; stdin = IOBuffer(svg.data)))
#     img = convert(Matrix{RGBA{N0f8}}, PNGFiles.load(IOBuffer(png)))

#     size(img) == (h, w) && return img

#     # resvg fits the image inside w×h preserving aspect ratio, so the result
#     # can be smaller in one dimension. Center it on a transparent canvas.
#     canvas = fill(RGBA{N0f8}(0, 0, 0, 0), h, w)
#     imstack!(canvas, img, (h - size(img, 1)) ÷ 2 + 1, (w - size(img, 2)) ÷ 2 + 1)
#     return canvas
# end

# function render(svg::SVGImage, dims::Tuple{Integer,Integer}; method = :auto)
#     h, w = dims
#     (h > 0 && w > 0) || throw(ArgumentError("target dimensions must be positive"))
#     cmd = `$(Librsvg_jll.rsvg_convert()) --width $w --height $h --format png`
#     png = read(pipeline(cmd; stdin = IOBuffer(svg.data)))
#     return convert(Matrix{RGBA{N0f8}}, PNGFiles.load(IOBuffer(png)))
# end

loadsvg(path) = SVGImage(read(path))

export loadsvg, render

end
