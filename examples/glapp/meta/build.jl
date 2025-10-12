using AppBundler

import TOML
import Pkg.BinaryPlatforms: Linux, MacOS, Windows

APP_DIR = dirname(@__DIR__)

BUILD_DIR = mktempdir()
@info "Build products will be created at $BUILD_DIR"

version = TOML.parsefile("$APP_DIR/Project.toml")["version"]

precompile = get(ENV, "PRECOMPILE", "true") == "true"
incremental = get(ENV, "INCREMENTAL", "false") == "true"
buildall = get(ENV, "BUILD_ALL", "false") == "true"

target_arch = get(ENV, "TARGET_ARCH", Sys.ARCH)
target_name = "peacefounder-$version-$(target_arch)"

if buildall || Sys.islinux()
    AppBundler.build_app(Linux(target_arch), APP_DIR, "$BUILD_DIR/$target_name.snap"; precompile, incremental)
end

if buildall || Sys.iswindows()
    AppBundler.build_app(Windows(target_arch), APP_DIR, "$BUILD_DIR/$target_name.msix"; precompile, incremental)
end

if buildall || Sys.isapple()
    AppBundler.build_app(MacOS(target_arch), APP_DIR, "$BUILD_DIR/$target_name.dmg"; precompile, incremental)
end
