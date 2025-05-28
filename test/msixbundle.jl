
import AppBundler: bundle_app
import Pkg.BinaryPlatforms: Windows


src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
#destination = joinpath(tempdir(), "gtkapp")
destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/gtkapp2"

rm(destination; force=true)

@info "Bundling app in $destination"

bundle_app(Windows(:x86_64), src_dir, destination)


