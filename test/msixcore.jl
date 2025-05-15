import AppBundler: build_app, MSIXPack
import Pkg.BinaryPlatforms: Windows

#src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")

destination = joinpath(homedir(), "Documents/gtkapp")
#destination = joinpath(homedir(), "Documents/qmlapp.msix")
rm(destination; recursive=true, force=true)

@info "Building app at $destination"
#build_app(Windows(:x86_64), src_dir, destination; precompile = Sys.iswindows())
#build_app(Windows(:x86_64), src_dir, destination; precompile = true)

build_app(Windows(:x86_64), src_dir, destination; incremental=false, precompile = true)

#build_app(Windows(:x86_64), src_dir, destination; incremental=true, precompile = true)


