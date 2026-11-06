using SafeTestsets

@time @safetestset "DS_Store parser" begin
    include("dsstore.jl")
end

@time @safetestset "HFSImg builder" begin
    include("hfsimg.jl")
end

