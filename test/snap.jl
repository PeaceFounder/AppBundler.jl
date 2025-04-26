import AppBundler: build_app
import Pkg.BinaryPlatforms: Linux

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")

snap_path = joinpath(tempdir(), "gtkapp.snap")
rm(snap_path; force=true)

# Precompilation is not yet integrated
# Debug flag is also unimplemented
# build_app(Linux(Sys.ARCH), src_dir, joinpath(build_dir, "gtkapp.snap"); precompile = Sys.linux())
build_app(Linux(Sys.ARCH), src_dir, snap_path)
