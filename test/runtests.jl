import AppBundler: julia_download_url, build_app
import Pkg.BinaryPlatforms: Linux, Windows, MacOS

using Test

@test julia_download_url(Windows(:x86_64), v"1.9.3") == "winnt/x64/1.9/julia-1.9.3-win64.zip"

@test julia_download_url(Linux(:x86_64, libc=:glibc), v"1.9.3") == "linux/x64/1.9/julia-1.9.3-linux-x86_64.tar.gz"
@test julia_download_url(Linux(:aarch64), v"1.9.3") == "linux/aarch64/1.9/julia-1.9.3-linux-aarch64.tar.gz"

@test julia_download_url(MacOS(:x86_64), v"1.9.3") == "mac/x64/1.9/julia-1.9.3-mac64.tar.gz"
@test julia_download_url(MacOS(:aarch64), v"1.9.3") == "mac/aarch64/1.9/julia-1.9.3-macaarch64.tar.gz"


if Sys.isunix()
    @info "Testing MacOS DMG bundling"

    platform = MacOS(:x86_64)

    build_dir = joinpath(tempdir(), "gtkapp_build")
    rm(build_dir; recursive=true, force=true)


    src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")


    build_app(platform, src_dir, joinpath(build_dir, "gtkapp.dmg"); debug = true, precompile = Sys.isapple())


    app_dir = joinpath(build_dir, "gtkapp/gtkapp.app")

    if Sys.isapple()

        @info "Verifying that the application is correctly codesigned"
        run(`codesign -v --verbose=4 $app_dir`)

    else

        @info "Codesigning verification skipped as codesign not available on this platform"

    end
    

    @info "Testing examples"

    @info "GTKApp"
    @eval include("../examples/gtkapp/meta/build.jl")
    @info "Mousetrap"
    @eval include("../examples/mousetrap/meta/build.jl")
    @info "QMLApp"
    @eval include("../examples/qmlapp/meta/build.jl")
    @info "GLApp"
    @eval include("../examples/glapp/meta/build.jl")

end


