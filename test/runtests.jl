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

@time @safetestset "GLApp example" begin

    using AppBundler

    app_dir = joinpath(dirname(@__DIR__), "examples/glapp")

    try
        AppBundler.install_github_workflow(; root = app_dir, force = true)
        AppBundler.generate_signing_certificates(; root = app_dir, force = true)

        push!(ARGS, "--compiled-modules=no")
        @eval include("../examples/glapp/meta/build.jl")
    finally
        # cleanup
        empty!(ARGS)
        rm(joinpath(app_dir, "meta/msix/certificate.pfx"); force = true)
        rm(joinpath(app_dir, "meta/dmg/certificate.pfx"); force = true)
        ENV["MACOS_PFX_PASSWORD"] = ""
        ENV["WINDOWS_PFX_PASSWORD"] = ""
    end
end

if get(ENV, "JULIA_RUN_EXAMPLES", "false") == "true"
    @time @safetestset "Examples" begin
        include("examples.jl")
    end
end
