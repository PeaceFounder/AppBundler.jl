using ICNS

source = joinpath(@__DIR__, "icon.png")
target = joinpath(@__DIR__, "output.icns")

generate_icns(source, target)
