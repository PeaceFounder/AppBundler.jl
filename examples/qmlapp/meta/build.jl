using AppBundler

import Pkg
import Pkg.BinaryPlatforms: Linux, MacOS, Windows

old_env = Base.active_project()

try
            
    APP_DIR = dirname(@__DIR__)

    BUILD_DIR = joinpath(APP_DIR, "build")
    mkpath(BUILD_DIR)

    AppBundler.bundle_app(MacOS(:x86_64), APP_DIR, "$BUILD_DIR/qmlapp-x64.app", splash_screen=true)
    AppBundler.bundle_app(MacOS(:aarch64), APP_DIR, "$BUILD_DIR/qmlapp-arm64.app", splash_screen=true)

    AppBundler.bundle_app(Linux(:x86_64), APP_DIR, "$BUILD_DIR/qmlapp-x64.snap")
    AppBundler.bundle_app(Linux(:aarch64), APP_DIR, "$BUILD_DIR/qmlapp-arm64.snap")
        
finally 
    Pkg.activate(old_env)
end
