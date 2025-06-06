import AppBundler: build_app
import Pkg.BinaryPlatforms: Linux

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
snap_path = joinpath(tempdir(), "gtkapp.snap")

build_app(Linux(Sys.ARCH), src_dir, snap_path; precompile = Sys.islinux())
