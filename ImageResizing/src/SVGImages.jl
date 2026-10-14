module SVGImages

using FileIO: File, Stream, @format_str, add_loader, filename, stream

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

fileio_load(f::File{format"SVG"}) = SVGImage(read(filename(f)))
fileio_load(s::Stream{format"SVG"}) = SVGImage(read(stream(s)))

#__init__() = (add_loader(format"SVG", @__MODULE__); nothing)

_init() = (add_loader(format"SVG", @__MODULE__); nothing)

#add_loader(format"SVG", @__MODULE__)

end
