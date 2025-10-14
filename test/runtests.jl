using SafeTestsets

# @time @safetestset "DS_Store parser" begin
#     include("dsstore.jl")
# end

# @time @safetestset "Bundling core tetsts" begin
#     include("bundle.jl")
# end

# @time @safetestset "Staging tests" begin
#     include("stage.jl")
# end

@time @safetestset "GLApp example" begin

    using AppBundler

    app_dir = joinpath(dirname(@__DIR__), "examples/glapp")

    try
        AppBundler.install_github_workflow(; root = app_dir, force = true)
        AppBundler.generate_signing_certificates(; root = app_dir, force = true)

        push!(ARGS, "--compiled-modules=no")
        #withenv("PRECOMPILE"=>"false", "TESTRUN"=>"true") do
        @eval include("../examples/glapp/meta/build.jl")
        #end
    finally
        # cleanup
        empty!(ARGS)
        rm(joinpath(app_dir, "meta/msix/certificate.pfx"); force = true)
        rm(joinpath(app_dir, "meta/dmg/certificate.pfx"); force = true)
        ENV["MACOS_PFX_PASSWORD"] = ""
        ENV["WINDOWS_PFX_PASSWORD"] = ""
    end
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
