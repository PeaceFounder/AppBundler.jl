using IconTools

outdir = joinpath(@__DIR__, "output")

source = joinpath(@__DIR__, "icon.png")
destination = joinpath(outdir, "icon-png.icns")

img = IconTools.load(source)
IconTools.toicns(img, destination)

source = joinpath(@__DIR__, "icon.svg")
destination = joinpath(outdir, "icon-svg.icns")

img = IconTools.load(source)
IconTools.toicns(img, destination)
