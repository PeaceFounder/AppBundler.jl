# staging example

import Pkg.BinaryPlatforms: MacOS, Linux, Windows
import AppBundler: stage, PkgImage

#src_dir = joinpath(dirname(@__DIR__), "examples/glapp")

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/mousetrap")


@show build_dir = mktempdir()

product_spec = PkgImage(src_dir; precompile = true)
#product_spec = PkgImage(src_dir; precompile = false)

if Sys.islinux()
    platform = Linux(Sys.ARCH)
elseif Sys.isapple()
    platform = MacOS(Sys.ARCH)
elseif Sys.iswindows()
    platform = Windows(Sys.ARCH)
end

stage(product_spec, platform, build_dir)

