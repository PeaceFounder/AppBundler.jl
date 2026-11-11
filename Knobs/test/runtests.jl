using Test

@testset "Knobs" begin
    @testset "Parsing and coercion" begin
        include("parsing.jl")
    end
    @testset "Layers and rules" begin
        include("layers.jl")
    end
end
