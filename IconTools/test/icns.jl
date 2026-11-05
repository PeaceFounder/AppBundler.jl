using IconTools

outdir = joinpath(@__DIR__, "build")

source = joinpath(pkgdir(IconTools), "assets/icon.png")
destination = joinpath(outdir, "icon-png.icns")

img = IconTools.load(source)
icns = IconTools.toicns(img)
write(destination, icns)

source = joinpath(pkgdir(IconTools), "assets/icon.svg")
destination = joinpath(outdir, "icon-svg.icns")

img = IconTools.load(source)
icns = IconTools.toicns(img)
write(destination, icns)
