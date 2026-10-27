using IconTools

outdir = joinpath(@__DIR__, "output")

source = joinpath(@__DIR__, "icon.png")
destination = joinpath(outdir, "icon-png")
rm(destination; recursive=true, force=true)
mkdir(destination)

img = IconTools.load(source)
icons = IconTools.tomsix(img)
for (key, value) in icons
    IconTools.save(joinpath(destination, key), value)
end

source = joinpath(@__DIR__, "icon.svg")
destination = joinpath(outdir, "icon-svg")
rm(destination; recursive=true, force=true)
mkdir(destination)

img = IconTools.load(source)
icons = IconTools.tomsix(img)

for (key, value) in icons
    IconTools.save(joinpath(destination, key), value)
end
