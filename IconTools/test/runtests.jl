using SafeTestsets

@time @safetestset "ImageResizing" begin
    include("imageresizing.jl")
end

@time @safetestset "SVGRenderer" begin
    include("svg_tests.jl")
end

@time @safetestset "ICNS" begin
    include("icns.jl")
end

@time @safetestset "MSIX" begin
    include("msixicons.jl")
end

@time @safetestset "README" begin
    include("readme.jl")
end

