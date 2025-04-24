import AppBundler: build_app
import Pkg.BinaryPlatforms: MacOS

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")

build_dir = joinpath(tempdir(), "gtkapp_build")
rm(build_dir; recursive=true, force=true)

#build_app(MacOS(:x86_64), src_dir, joinpath(build_dir, "gtkapp.dmg"); debug = true, precompile = Sys.isapple())
build_app(MacOS(:x86_64), src_dir, joinpath(build_dir, "gtkapp.dmg"); debug = true, precompile = true)

app_dir = joinpath(build_dir, "gtkapp/gtkapp.app")

if Sys.isapple()

    @info "Verifying that the application is correctly codesigned"
    run(`codesign -v --verbose=4 $app_dir`)

else

    @info "Codesigning verification skipped as codesign not available on this platform"

end
