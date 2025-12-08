import Pkg.BinaryPlatforms: MacOS, Linux, Windows
import AppBundler: stage, JuliaAppBundle
import AppBundler

import AppBundler.Resources: julia_download_url
#import AppBundler.Stage: julia_download_url
import Pkg.BinaryPlatforms: Linux, Windows, MacOS

using Test

@time @testset "Julia download link test" begin

    @test julia_download_url(Windows(:x86_64), v"1.9.3") == "winnt/x64/1.9/julia-1.9.3-win64.tar.gz"

    @test julia_download_url(Linux(:x86_64, libc=:glibc), v"1.9.3") == "linux/x64/1.9/julia-1.9.3-linux-x86_64.tar.gz"
    @test julia_download_url(Linux(:aarch64), v"1.9.3") == "linux/aarch64/1.9/julia-1.9.3-linux-aarch64.tar.gz"

    @test julia_download_url(MacOS(:x86_64), v"1.9.3") == "mac/x64/1.9/julia-1.9.3-mac64.tar.gz"
    @test julia_download_url(MacOS(:aarch64), v"1.9.3") == "mac/aarch64/1.9/julia-1.9.3-macaarch64.tar.gz"
end

#src_dir = dirname(@__DIR__) # AppBundler itself
#src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/mousetrap")

if Sys.islinux()
    platform = Linux(Sys.ARCH)
elseif Sys.isapple()
    platform = MacOS(Sys.ARCH)
elseif Sys.iswindows()
    platform = Windows(Sys.ARCH)
end

src_dir = joinpath(pkgdir(AppBundler), "examples/GLApp")

product_spec = JuliaAppBundle(src_dir; precompile = true)
stage(product_spec, platform, mktempdir())

asset_spec = Dict{Symbol, Vector{String}}(
    :AppEnv => ["LICENSE"]
)

product_spec = JuliaAppBundle(src_dir; precompile = true, sysimg_packages = ["GLApp"], asset_spec, asset_rpath = "assets", remove_sources=true)
stage(product_spec, platform, mktempdir(); cpu_target="native")

# # Tests sysimg generation with Julia 1.12
src_dir = joinpath(pkgdir(AppBundler), "examples/CmdApp")
product_spec = JuliaAppBundle(src_dir; precompile = true, sysimg_packages = ["CmdApp"], remove_sources=true)
stage(product_spec, platform, mktempdir(); cpu_target="native")
