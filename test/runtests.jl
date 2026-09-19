using SafeTestsets

@time @safetestset "ArgTools parser" begin
    include("argtools.jl")
end

@time @safetestset "DS_Store parser" begin
    include("dsstore.jl")
end

@time @safetestset "Bundling core tetsts" begin
    include("bundle.jl")
end

@time @safetestset "Staging tests" begin
    include("juliaimg.jl")
end

@time @safetestset "JuliaC staging tests" begin
    include("juliac.jl")
end

@time @safetestset "CLI API example" begin
    include("integrity.jl")
end

if get(ENV, "JULIA_RUN_EXAMPLES", "false") == "true"
    @time @safetestset "Examples" begin
        include("examples.jl")
    end
end
