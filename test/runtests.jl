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

# if Sys.isunix()

#     if get(ENV, "JULIA_RUN_EXAMPLES", "false") == "true"
#         @info "Running extensive example tests"
        
# @time @safetestset "GTKApp Example" begin
#    include("../examples/gtkapp/meta/build.jl")
# end

#         @time @safetestset "Mousetrap Example" begin
#             include("../examples/mousetrap/meta/build.jl")
#         end

#         @time @safetestset "QMLApp Example" begin
#             include("../examples/qmlapp/meta/build.jl")
#         end

#         @time @safetestset "GLApp Example" begin
#             include("../examples/glapp/meta/build.jl")
#         end
        
#     else
#         @info "Skipping example tests (set JULIA_RUN_EXAMPLES=true to run)"
#     end

# end
