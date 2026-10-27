using IconTools

outdir = joinpath(@__DIR__, "output")

source = joinpath(@__DIR__, "icon.png")
destination = joinpath(outdir, "icon-png.icns")

img = IconTools.load(source)
icns = IconTools.toicns(img)
write(destination, icns)

source = joinpath(@__DIR__, "icon.svg")
destination = joinpath(outdir, "icon-svg.icns")

img = IconTools.load(source)
icns = IconTools.toicns(img)
write(destination, icns)
