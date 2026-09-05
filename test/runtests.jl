using SafeTestsets

@time @safetestset "DS_Store parser" begin
    include("dsstore.jl")
end

@time @safetestset "Bundling core tetsts" begin
    include("bundle.jl")
end

@time @safetestset "Staging tests" begin
    include("stage.jl")
end

@time @safetestset "JuliaC staging tests" begin
    include("juliac.jl")
end

@time @safetestset "Tarball packing tests" begin
    include("tarball.jl")
end

@time @safetestset "Juliaup version database tests" begin
    include("juliaup.jl")
end

@time @safetestset "CLI API example" begin
    include("integrity.jl")
end

if get(ENV, "JULIA_RUN_JULIAUP_E2E", "false") == "true"
    @time @safetestset "Juliaup end to end" begin
        include("juliaup_e2e.jl")
    end
end

if get(ENV, "JULIA_RUN_EXAMPLES", "false") == "true"
    @time @safetestset "Examples" begin
        include("examples.jl")
    end
end
