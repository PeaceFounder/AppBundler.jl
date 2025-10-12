using AppBundler

import Pkg.BinaryPlatforms: Linux, MacOS, Windows

APP_DIR = dirname(@__DIR__)

BUILD_DIR = joinpath(APP_DIR, "build")
mkpath(BUILD_DIR)

precompile = false
incremental = false
runall = false

target_arch = get(ENV, "TARGET_ARCH", Sys.arch)
target_name = "{{APP_NAME}}-$(target_arch)"

if runall || Sys.islinux()
    AppBundler.build_app(Linux(target_arch), APP_DIR, "$BUILD_DIR/$target_name.snap"; precompile, incremental)
end

if runall || Sys.iswindows()
    AppBundler.build_app(Windows(target_arch), APP_DIR, "$BUILD_DIR/$target_name.msix"; precompile, incremental)
end

if runall || Sys.ismacos()
    AppBundler.build_app(MacOS(target_arch), APP_DIR, "$BUILD_DIR/$target_name.dmg"; precompile, incremental)
end
