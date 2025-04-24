using AppBundler

import Pkg.BinaryPlatforms: Linux, MacOS, Windows

APP_DIR = dirname(@__DIR__)

BUILD_DIR = joinpath(APP_DIR, "build")
mkpath(BUILD_DIR)


#AppBundler.build_app(MacOS(:x86_64), APP_DIR, "$BUILD_DIR/qmlapp-x64.dmg", precompile = Sys.isapple())
AppBundler.build_app(MacOS(:aarch64), APP_DIR, "$BUILD_DIR/qmlapp-arm64.dmg", precompile = Sys.isapple() && Sys.ARCH == :aarch64)

# AppBundler.build_app(Linux(:x86_64), APP_DIR, "$BUILD_DIR/qmlapp-x64.snap")
# AppBundler.build_app(Linux(:aarch64), APP_DIR, "$BUILD_DIR/qmlapp-arm64.snap")

# AppBundler.build_app(Windows(:x86_64), APP_DIR, "$BUILD_DIR/qmlapp-win64.zip")
