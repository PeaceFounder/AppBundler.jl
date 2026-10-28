module MSIXIcons

import PNGFiles: save
using ..IconForge: toicon, totile
using Colors
using FixedPointNumbers

const SCALES   = (100, 125, 150, 200, 400)
const ALTFORMS = ("_altform-unplated", "_altform-lightunplated")

# (name, base width, base height, scales)
const SQUARE_LOGOS = [
    ("BadgeLogo",           24,  24, SCALES),
    ("Square30x30Logo",     30,  30, (100,)),
    ("Square44x44Logo",     44,  44, SCALES),
    ("Square70x70Logo",     70,  70, (100,)),
    ("Square71x71Logo",     71,  71, SCALES),
    ("Square150x150Logo",  150, 150, SCALES),
    ("Square310x310Logo",  310, 310, SCALES),
    ("Square310x310Logo1", 310, 310, SCALES),
]

# (name, base width, base height, target sizes)
const SQUARE_ALT_LOGOS = [
    ("Square44x44Logo", 44, 44, (16, 24, 32, 48, 256)),
]

const WIDE_LOGOS   = [("Wide310x150Logo", 310, 150, SCALES)]
const SPLASH_LOGOS = [("SplashScreen",    620, 300, SCALES)]

const DEFAULT_PLATE = RGBA{Float32}(0.01, 0.45, 0.78, 1.0)

scaled(n, s) = round(Int, n * s / 100, RoundNearestTiesUp)

function logo_specs(logos; qualifier = "scale", altforms = false)
    dims(n, v) = qualifier == "scale" ? scaled(n, v) : v
    suffixes   = altforms ? ("", ALTFORMS...) : ("",)
    return [("$name.$qualifier-$v$alt.png", dims(w, v), dims(h, v))
            for (name, w, h, values) in logos
            for v in values
            for alt in suffixes]
end

# Render each (file, w, h) spec once per distinct size; files with the same
# size share one matrix.
function render_specs(render, specs; cache = Dict{Tuple{Int,Int},Matrix{RGBA{N0f8}}}())
    return [file => get!(() -> render(w, h), cache, (w, h)) for (file, w, h) in specs]
end

square_logos(img; altforms = true, kwargs...) = render_specs(
    (w, _) -> toicon(img, w),
    [logo_specs(SQUARE_LOGOS);
     logo_specs(SQUARE_ALT_LOGOS; qualifier = "targetsize", altforms)]; kwargs...)

wide_logos(img; kwargs...) =
    render_specs((w, h) -> totile(img, w, h), logo_specs(WIDE_LOGOS); kwargs...)

splash_logos(img; background = DEFAULT_PLATE, kwargs...) =
    render_specs((w, h) -> totile(img, w, h; background), logo_specs(SPLASH_LOGOS); kwargs...)


_tocolor(x) = x isa String ? parse(RGBA{N0f8}, x) : x

"""
    tomsix(img; altforms = true, splash_background, store_background)
        -> Vector{Pair{String, Matrix{RGBA{N0f8}}}}

Render the full set of MSIX package icons from `img` and return them as
`filename => image` pairs. Set `altforms = false` to skip the unplated
target-size variants. Write them out with [`write_msix`](@ref):

    write_msix("build/msix", tomsix(img))

Files with identical pixel sizes share the same matrix; `copy` an image
before modifying it in place.
"""
function tomsix(img; altforms = true,
                splash_icon_plate = DEFAULT_PLATE,
                store_icon_plate  = DEFAULT_PLATE)

    #cache = Dict{Tuple{Int,Int},Matrix{RGBA{N0f8}}}()

    return [square_logos(img; altforms);
            wide_logos(img);
            splash_logos(img; background = _tocolor(splash_icon_plate));
            "StoreLogo.scale-100.png" => toicon(img, 150; background = _tocolor(store_icon_plate))
            ]
end

end
