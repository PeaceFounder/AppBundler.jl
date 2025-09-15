# staging example

import Pkg.BinaryPlatforms: MacOS
import AppBundler: stage, PkgImage

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")

@show build_dir = joinpath(tempdir(), "gtkapp_build")
rm(build_dir; recursive=true, force=true)
mkpath(build_dir)

product_spec = PkgImage(src_dir)

stage(product_spec, MacOS(:x86_64), build_dir)
