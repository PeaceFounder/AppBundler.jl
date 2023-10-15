import Pkg
import Pkg.BinaryPlatforms: Linux, MacOS, Windows

old_env = Base.active_project()

try
    temp_env = mktempdir()
    Pkg.activate(temp_env)

    Pkg.develop(path=joinpath(homedir(), "BtSync", "PeaceFounder", "GitHub", "AppBundler"))

    using AppBundler
            
    APP_DIR = dirname(@__DIR__)

    BUILD_DIR = joinpath(APP_DIR, "build")
    rm(BUILD_DIR, force=true, recursive=true)
    mkdir(BUILD_DIR)

    AppBundler.bundle_app(MacOS(:x86_64), APP_DIR, "$BUILD_DIR/gtkapp-x64.app")
    AppBundler.bundle_app(MacOS(:aarch64), APP_DIR, "$BUILD_DIR/gtkapp-arm64.app")

    AppBundler.bundle_app(Linux(:x86_64), APP_DIR, "$BUILD_DIR/gtkapp-x64.snap")
    AppBundler.bundle_app(Linux(:aarch64), APP_DIR, "$BUILD_DIR/gtkapp-arm64.snap")
        
finally 
    Pkg.activate(old_env)
end
