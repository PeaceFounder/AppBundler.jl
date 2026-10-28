# IconTools.jl

Generate application icons for desktop platforms from a single PNG or SVG source, in pure Julia.

IconTools takes one master image and produces the platform-specific icon sets that installers expect: an `.icns` bundle for macOS and the full set of tile and logo assets for an MSIX package on Windows. SVG sources are rasterized directly at each target size, so vector icons stay sharp at every resolution; PNG sources are resampled with filters chosen for the direction of scaling.

## Installation

```julia
pkg> add IconTools
```

## Quick start

```julia
using IconTools

img = IconTools.load("icon.svg")          # or "icon.png"

# single PNG icon, e.g. for Linux
IconTools.save("build/icon-256.png", IconTools.toicon(img, 256))

# macOS icon bundle
write("build/MyApp.icns", IconTools.toicns(img))

# Windows MSIX assets
mkpath("build/msix")
for (file, icon) in IconTools.tomsix(img)
    IconTools.save(joinpath("build/msix", file), icon)
end
```

`IconTools.load` accepts either format and returns an image that every generator understands. For best results, start from an SVG or from a square PNG of at least 1024×1024 pixels.

## Icon generators

| Function | Output | Platform |
|---|---|---|
| `toicon(img, side; background)` | A single square icon of `side`×`side` pixels | Any |
| `totile(img, width, height; scale, background)` | The icon centred on a `width`×`height` canvas | Any |
| `toicns(img; toc)` | The bytes of an `.icns` file with all standard macOS icon sizes; write them with `write(path, ...)` | macOS |
| `tomsix(img; altforms, splash_background, store_background)` | `filename => image` pairs for all MSIX logo and tile assets | Windows |

Each generator renders every size it needs from the source independently. With an SVG source, that means a fresh rasterization per size rather than downscaling one large bitmap.

Both platform generators return values rather than writing files, so the output can go to disk, into an archive or into a build step. `toicns` returns the encoded file as `Vector{UInt8}`. `tomsix` returns `filename => image` pairs, so individual assets can be replaced before saving:

```julia
assets = IconTools.tomsix(img; altforms = false, splash_background = RGBA(1, 1, 1, 1))
assets = filter(((file, _),) -> !startswith(file, "SplashScreen"), assets)  # drop the splash screens
```

Assets with identical pixel sizes share one matrix, so `copy` an image before modifying it in place.

### Single icons and tiles

For a single bitmap, for example a Linux desktop icon or a favicon, use `toicon`. The source must be square:

```julia
icon = IconTools.toicon(img, 256)   # 256×256, transparency preserved
IconTools.save("icon-256.png", icon)

# flatten onto a solid background
icon = IconTools.toicon(img, 256; background = RGBA(1, 1, 1, 1))
```

For non-square assets such as splash screens, banners or store tiles, use `totile`. It renders the icon as a square and centres it on a `width`×`height` canvas:

```julia
# 620×300 wide tile, icon at 80% of the shorter side, transparent background
tile = IconTools.totile(img, 620, 300; scale = 0.8)

# same tile on a solid brand colour
tile = IconTools.totile(img, 620, 300; scale = 0.8,
                        background = RGBA(0.16, 0.50, 0.52, 1.0))
```

The icon side is `round(min(width, height) * scale)`, so `scale = 1` fills the shorter dimension and smaller values add padding. Note that `totile` takes `width, height` in that order.

Both functions rasterize SVG sources directly at the target size and resample PNG sources.
