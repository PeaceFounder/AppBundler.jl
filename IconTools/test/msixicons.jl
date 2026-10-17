using IconTools

outdir = joinpath(@__DIR__, "output")

source = joinpath(@__DIR__, "icon.png")
destination = joinpath(outdir, "icon-png")
rm(destination; recursive=true, force=true)

img = IconTools.load(source)
IconTools.msix_icons(img, destination)


source = joinpath(@__DIR__, "icon.svg")
destination = joinpath(outdir, "icon-svg")
rm(destination; recursive=true, force=true)

img = IconTools.load(source)
IconTools.msix_icons(img, destination)


# img = IconTools.load(source)
# IconTools.toicns(img, destination)

# source = joinpath(@__DIR__, "icon.svg")
# outdir = joinpath(@__DIR__, "output/icon-png")
# rm(outdir; recursive=true, force=true)




