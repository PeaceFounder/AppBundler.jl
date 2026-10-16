module MSIXIcons

import PNGFiles: save
using ..IconForge: toicon, totile
using ColorTypes

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

scaled(n, s) = round(Int, n * s / 100, RoundNearestTiesUp)

function logo_specs(logos; qualifier = "scale", altforms = false)
    dims(n, v) = qualifier == "scale" ? scaled(n, v) : v
    suffixes   = altforms ? ("", ALTFORMS...) : ("",)
    return [("$name.$qualifier-$v$alt.png", dims(w, v), dims(h, v))
            for (name, w, h, values) in logos
            for v in values
            for alt in suffixes]
end

function write_icons(render, output_dir, specs)
    cache = Dict{Tuple{Int,Int},Any}()
    for (file, w, h) in specs
        save(joinpath(output_dir, file), get!(() -> render(w, h), cache, (w, h)))
    end
end

function square_logos(img, output_dir; altforms = true)
    specs = [logo_specs(SQUARE_LOGOS);
             logo_specs(SQUARE_ALT_LOGOS; qualifier = "targetsize", altforms)]
    write_icons((w, h) -> toicon(img, w), output_dir, specs)
end

wide_logos(img, output_dir) =
    write_icons((w, h) -> totile(img, w, h), output_dir, logo_specs(WIDE_LOGOS))

function splash_logos(img, output_dir; background = RGBA{Float32}(0.01, 0.45, 0.78, 1.0))
    write_icons((w, h) -> totile(img, w, h; background), output_dir, logo_specs(SPLASH_LOGOS))
end

"""
    msix_icons(img, output_dir; altforms = true)

Generate the full set of MSIX package icons from a single source image `img`
into `output_dir`. Set `altforms = false` to skip the unplated target-size variants.
"""
function msix_icons(img, output_dir::AbstractString; altforms = true, store_icon_background = RGBA{Float32}(0.01, 0.45, 0.78, 1.0))

    mkpath(output_dir)
    square_logos(img, output_dir; altforms)
    wide_logos(img, output_dir)
    splash_logos(img, output_dir)

    store_icon = toicon(img, 150; background = store_icon_background)
    save(joinpath(output_dir, "StoreLogo.scale-100.png"), store_icon)
    
    return
end

end
