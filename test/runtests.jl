using SafeTestsets
import AppBundler: julia_download_url
import Pkg.BinaryPlatforms: Linux, Windows, MacOS

using Test

@time @testset "Julia download link test" begin

    @test julia_download_url(Windows(:x86_64), v"1.9.3") == "winnt/x64/1.9/julia-1.9.3-win64.zip"

    @test julia_download_url(Linux(:x86_64, libc=:glibc), v"1.9.3") == "linux/x64/1.9/julia-1.9.3-linux-x86_64.tar.gz"
    @test julia_download_url(Linux(:aarch64), v"1.9.3") == "linux/aarch64/1.9/julia-1.9.3-linux-aarch64.tar.gz"

    @test julia_download_url(MacOS(:x86_64), v"1.9.3") == "mac/x64/1.9/julia-1.9.3-mac64.tar.gz"
    @test julia_download_url(MacOS(:aarch64), v"1.9.3") == "mac/aarch64/1.9/julia-1.9.3-macaarch64.tar.gz"
end

@time @safetestset "DS_Store parser" begin
    include("dsstore.jl")
end

@time @safetestset "MSIX building tests" begin
    include("msix.jl")
end

if Sys.isunix()

    @time @safetestset "DMG building tests" begin
        include("dmg.jl")
    end

    @time @safetestset "Snap building tests" begin
        include("snap.jl")
    end

    if get(ENV, "JULIA_RUN_EXAMPLES", "false") == "true"
        @info "Running extensive example tests"
        
        @time @safetestset "GTKApp Example" begin
            include("../examples/gtkapp/meta/build.jl")
        end

        @time @safetestset "Mousetrap Example" begin
            include("../examples/mousetrap/meta/build.jl")
        end

        @time @safetestset "QMLApp Example" begin
            include("../examples/qmlapp/meta/build.jl")
        end

        @time @safetestset "GLApp Example" begin
            include("../examples/glapp/meta/build.jl")
        end
        
    else
        @info "Skipping example tests (set JULIA_RUN_EXAMPLES=true to run)"
    end

end
