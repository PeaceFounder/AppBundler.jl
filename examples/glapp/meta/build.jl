using AppBundler

import Pkg.BinaryPlatforms: Linux, MacOS, Windows

APP_DIR = dirname(@__DIR__)

BUILD_DIR = joinpath(APP_DIR, "build")
mkpath(BUILD_DIR)

AppBundler.build_app(Linux(:x86_64), APP_DIR, "$BUILD_DIR/glapp-x64.snap")
