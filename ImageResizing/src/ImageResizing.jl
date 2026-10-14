"""
    ImageResizing

Two array operations for building raster images without ImageTransformations,
plus SVG rasterization:

    imresize(img, h, w; method = :auto)   # resample to h×w
    imresize(color, h, w)                 # solid h×w canvas of `color`
    imresize(svg::SVGImage, h, w)         # rasterize an SVG to h×w (RGBA{N0f8})
    imstack!(canvas, img, top, left)      # alpha-composite `img` onto `canvas`

Loading and saving are left to `FileIO`/`ImageIO`. `FileIO.load("icon.svg")`
returns an `SVGImage` (registered by the `SVGImages` submodule); it is
rasterized by `imresize` via the `rsvg-convert` executable from `Librsvg_jll`.
Typical workflow:

    using FileIO, ImageResizing
    canvas = imresize(RGB(1, 1, 1), 600, 800)
    icon   = imresize(load("icon.svg"), 200, 300)   # or load("icon.png")
    imstack!(canvas, icon, 100, 100)
    save("result.png", canvas)

Coordinates follow Julia array order: `h`/`top` are rows (y), `w`/`left` are
columns (x), and `top`/`left` are the 1-based canvas indices where the
top-left pixel of `img` lands.

Suggested Project.toml compat:

    ColorTypes = "0.11, 0.12"
    ColorVectorSpace = "0.10, 0.11"
    FixedPointNumbers = "0.8"
    FileIO = "1"
    PNGFiles = "0.4"
    Librsvg_jll = "2"
"""
module ImageResizing

using ColorTypes
using ColorVectorSpace
using FixedPointNumbers: FixedPoint, N0f8
import PNGFiles
import Librsvg_jll

export imresize, imstack!, SVGImage

# ---- SVGImages submodule -----------------------------------------------------

include("SVGImages.jl")

using .SVGImages: SVGImage
function __init__()
    #SVGImages.__init__()
    SVGImages._init()
end

# ---- pixel promotion --------------------------------------------------------
# Arithmetic on colorants comes from ColorVectorSpace; pixels are promoted to
# Float64 channels first so fixed-point types cannot overflow mid-computation.

_float(x::Number) = Float64(x)
_float(c::Colorant) = convert(base_colorant_type(typeof(c)){Float64}, c)

_lerp(a, b, t) = (1 - t) * _float(a) + t * _float(b)

_zero(x::Number) = 0.0
_zero(c::Colorant) = zero(typeof(_float(c)))

_convert(::Type{T}, x::Number) where {T<:Number} = convert(T, x)
function _convert(::Type{T}, c::Colorant) where {T<:Colorant}
    if eltype(T) <: FixedPoint
        c = mapc(x -> clamp(x, 0.0, 1.0), c)
    end
    return convert(T, c)
end

# ---- imresize --------------------------------------------------------------

"""
    imresize(img, h, w; method = :auto)
    imresize(img, (h, w); method = :auto)

Resize `img` to `h`×`w`. `method` is `:bilinear`, `:area` (box averaging with
fractional pixel coverage — the right choice for downscaling, e.g. icons), or
`:auto`, which picks `:area` when the output is smaller than the input and
`:bilinear` otherwise. The output has the same element type as `img`.

    imresize(color, h, w)

Create a solid `h`×`w` canvas filled with `color` (a `Colorant`, or a number
for grayscale). Equivalent to resizing a 1×1 image.

    imresize(svg::SVGImage, h, w)

Rasterize an SVG (as returned by `FileIO.load` on an `.svg` file) directly at
`h`×`w` using librsvg. Like the raster method this maps the source onto the
target box exactly (no aspect preservation); pick `h`, `w` from
`svg.height`/`svg.width` if you want the aspect kept. Returns
`Matrix{RGBA{N0f8}}`; `method` is ignored.
"""
imresize(img::Union{AbstractMatrix,SVGImage}, h::Integer, w::Integer; kwargs...) =
    imresize(img, (h, w); kwargs...)

imresize(c::Union{Colorant,Number}, h::Integer, w::Integer; kwargs...) =
    imresize(c, (h, w); kwargs...)

function imresize(c::Union{Colorant,Number}, dims::Tuple{Integer,Integer}; method = :auto)
    h, w = dims
    (h > 0 && w > 0) || throw(ArgumentError("canvas dimensions must be positive"))
    return fill(c, h, w)
end

function imresize(svg::SVGImage, dims::Tuple{Integer,Integer}; method = :auto)
    h, w = dims
    (h > 0 && w > 0) || throw(ArgumentError("target dimensions must be positive"))
    cmd = `$(Librsvg_jll.rsvg_convert()) --width $w --height $h --format png`
    png = read(pipeline(cmd; stdin = IOBuffer(svg.data)))
    return convert(Matrix{RGBA{N0f8}}, PNGFiles.load(IOBuffer(png)))
end

function imresize(img::AbstractMatrix{T}, dims::Tuple{Integer,Integer};
                  method::Symbol = :auto) where {T}
    h, w = dims
    (h > 0 && w > 0) || throw(ArgumentError("target dimensions must be positive"))
    size(img) == (h, w) && return Matrix{T}(img)
    if method === :auto
        method = h * w < length(img) ? :area : :bilinear
    end
    method === :bilinear && return _bilinear(img, h, w)
    method === :area && return _area(img, h, w)
    throw(ArgumentError("unknown method $method; use :bilinear or :area"))
end

function _bilinear(img::AbstractMatrix{T}, h::Int, w::Int) where {T}
    H, W = size(img)
    out = Matrix{T}(undef, h, w)
    sy, sx = H / h, W / w
    @inbounds for j in 1:w
        # map output pixel center to input coordinates
        x = (j - 0.5) * sx + 0.5
        x0 = clamp(floor(Int, x), 1, W)
        x1 = min(x0 + 1, W)
        fx = clamp(x - x0, 0.0, 1.0)
        for i in 1:h
            y = (i - 0.5) * sy + 0.5
            y0 = clamp(floor(Int, y), 1, H)
            y1 = min(y0 + 1, H)
            fy = clamp(y - y0, 0.0, 1.0)
            top = _lerp(img[y0, x0], img[y0, x1], fx)
            bot = _lerp(img[y1, x0], img[y1, x1], fx)
            out[i, j] = _convert(T, _lerp(top, bot, fy))
        end
    end
    return out
end

function _area(img::AbstractMatrix{T}, h::Int, w::Int) where {T}
    H, W = size(img)
    out = Matrix{T}(undef, h, w)
    sy, sx = H / h, W / w
    z = _zero(first(img))
    @inbounds for j in 1:w
        xs, xe = (j - 1) * sx, j * sx
        for i in 1:h
            ys, ye = (i - 1) * sy, i * sy
            acc = z
            total = 0.0
            for x in (floor(Int, xs) + 1):min(ceil(Int, xe), W)
                wx = min(xe, x) - max(xs, x - 1)
                wx <= 0 && continue
                for y in (floor(Int, ys) + 1):min(ceil(Int, ye), H)
                    wy = min(ye, y) - max(ys, y - 1)
                    wy <= 0 && continue
                    wgt = wx * wy
                    acc += _float(img[y, x]) * wgt
                    total += wgt
                end
            end
            out[i, j] = _convert(T, acc / total)
        end
    end
    return out
end

# ---- imstack! ---------------------------------------------------------------

# Porter–Duff "over": src on top of dst. Result is in dst's colorant family,
# promoted to Float64 channels; caller converts back to the canvas type.

# opaque source (or plain numbers) simply overwrites
_over(src::Union{Color,Number}, dst) = _float(src)

# transparent source over opaque destination
function _over(src::TransparentColor, dst::Color)
    a = Float64(alpha(src))
    return a * _float(color(src)) + (1 - a) * _float(dst)
end

# transparent source over transparent destination (unpremultiplied over)
function _over(src::TransparentColor, dst::TransparentColor)
    as, ad = Float64(alpha(src)), Float64(alpha(dst))
    ao = as + ad * (1 - as)
    ao == 0 && return _zero(dst)
    c = (as * _float(color(src)) + ad * (1 - as) * _float(color(dst))) / ao
    return alphacolor(c, ao)
end

"""
    imstack!(canvas, img, top, left)

Composite `img` onto `canvas` in place, with the top-left pixel of `img` at
`canvas[top, left]` (1-based row/column). Transparent pixels in `img` are
alpha-blended over the canvas (Porter–Duff *over*); opaque pixels overwrite.
Parts of `img` that fall outside the canvas are clipped, and offsets may be
zero or negative. Returns `canvas`.
"""
function imstack!(canvas::AbstractMatrix{T}, img::AbstractMatrix,
                  top::Integer, left::Integer) where {T}
    H, W = size(canvas)
    h, w = size(img)
    # overlapping index ranges in canvas coordinates
    i_range = max(top, 1):min(top + h - 1, H)
    j_range = max(left, 1):min(left + w - 1, W)
    @inbounds for j in j_range, i in i_range
        canvas[i, j] = _convert(T, _over(img[i - top + 1, j - left + 1], canvas[i, j]))
    end
    return canvas
end

end # module

