module IconForge

import ..ImageResizing
import ..SVGRenderer
import ..SVGRenderer: SVGImage
using ColorTypes
using FixedPointNumbers

"""
    load(path::AbstractString)

Load an image by file extension (case-insensitive):

- `.png` returns a `Matrix` of colorants (see [`pngload`](@ref)).
- `.svg` returns an [`SVGImage`](@ref); rasterize it with `imresize(svg, h, w)`.

Other extensions throw an `ArgumentError`.
"""
function load(path::AbstractString)
    isfile(path) || throw(ArgumentError("file not found: $path"))
    ext = lowercase(splitext(path)[2])
    if ext == ".png"
        return ImageResizing.load(path)
    elseif ext == ".svg"
        return SVGRenderer.load(path)
    else
        throw(ArgumentError("unsupported image format \"$ext\"; use .png or .svg"))
    end
end


function render(img::AbstractMatrix{T}, h::Int, w::Int) where {T}
    return ImageResizing.imresize(img, h, w)
end

function render(img::SVGImage, h::Int, w::Int)
    return SVGRenderer.render(img, h, w)
end


function issquare(img::SVGImage)
    return img.width == img.height
end

function issquare(img::AbstractMatrix{T}) where {T}
    w, h = size(img)
    return w == h
end


# """
#     square_pad(img)

# Centre a non-square image on a transparent square canvas. Note Julia indexes
# images as (row, col) == (height, width), the transpose of PIL's `size`.
# """
# function square_pad(img::AbstractMatrix{<:Colorant})
#     h, w = size(img)
#     h == w && return convert(Matrix{RGBA{N0f8}}, img)

#     n = max(h, w)
#     out = fill(RGBA{N0f8}(0, 0, 0, 0), n, n)
#     y0 = (n - h) ÷ 2
#     x0 = (n - w) ÷ 2
#     out[y0+1:y0+h, x0+1:x0+w] .= RGBA{N0f8}.(img)
#     return out
# end


function toicon(img, side::Integer; background::Union{RGBA, Nothing} = nothing)
    issquare(img) || throw(ArgumentError("img is not square"))

    icon = render(img, side, side)

    if isnothing(background) 
        return icon
    else
        canvas = fill(background, side, side)
        return ImageResizing.imstack!(canvas, icon, 1, 1)
    end
end


function totile(img, width::Integer, height::Integer; scale::Real = 1,
                background::RGBA = RGBA{Float32}(0.0, 0.0, 0.0, 0.0))
    (width > 0 && height > 0) || throw(ArgumentError("tile dimensions must be positive"))
    scale > 0 || throw(ArgumentError("scale must be positive"))

    side = max(1, round(Int, min(width, height) * scale))
    icon = render(img, side, side)

    canvas = fill(convert(RGBA{N0f8}, background), height, width)

    top  = (height - side) ÷ 2 + 1
    left = (width  - side) ÷ 2 + 1
    return ImageResizing.imstack!(canvas, icon, top, left)
end

# render(img) would also work just fine

export totile, toicon, load


end
