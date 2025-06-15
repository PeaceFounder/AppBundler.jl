using Test
import AppBundler: build_app, build_dmg, retrieve_macos_launcher
import Pkg.BinaryPlatforms: MacOS

src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")

build_dir = joinpath(tempdir(), "gtkapp_build")
rm(build_dir; recursive=true, force=true)
mkdir(build_dir)

# Building check
build_dmg(src_dir, joinpath(build_dir, "gtkapp.dmg")) do app_stage

    @test isdir(app_stage)

    mkpath(joinpath(app_stage, "Contents/MacOS"))
    retrieve_macos_launcher(MacOS(:x86_64), joinpath(app_stage, "Contents/MacOS/gtkapp"))

end

app_dir = joinpath(build_dir, "gtkapp/gtkapp.app")
build_app(MacOS(:x86_64), src_dir, app_dir; precompile = Sys.isapple())

if Sys.isapple()

    @info "Verifying that the application is correctly codesigned"
    run(`codesign -v --verbose=4 $app_dir`)

    @info "Checking any invalidations of precompilation cache"
    orig_app_dir = app_dir
    temp_app_dir = joinpath(dirname(app_dir), "gtk_app_tmp")
    try 
        julia_exe = joinpath(temp_app_dir, "Contents/Libraries/julia/bin/julia")
        mv(orig_app_dir, temp_app_dir)
        run(`$julia_exe --compiled-modules=strict --pkgimages=existing --eval="using GTKApp"`)
    finally
        isdir(temp_app_dir) && mv(temp_app_dir, orig_app_dir)
    end
else

    @info "Codesigning verification and precompilation invalidation check skipped as codesign not available on this platform"

end
