using AppBundler

APP_DIR = dirname(@__DIR__)

if get(ENV, "TESTRUN", "false") == "true"
    BUILD_DIR = mktempdir()
else
    BUILD_DIR = joinpath(APP_DIR, "build")
    mkpath(BUILD_DIR)
end
@info "Build products will be created at $BUILD_DIR"

precompile = get(ENV, "PRECOMPILE", "true") == "true"
incremental = get(ENV, "INCREMENTAL", "false") == "true"
buildall = get(ENV, "BUILD_ALL", "false") == "true"

target_arch = get(ENV, "TARGET_ARCH", Sys.ARCH)
version = AppBundler.get_version(APP_DIR)
target_name = "glapp-$version-$(target_arch)"

if buildall || Sys.islinux()
    AppBundler.build_app(Linux(target_arch), APP_DIR, "$BUILD_DIR/$target_name.snap"; precompile, incremental)
end

if buildall || Sys.iswindows()
    AppBundler.build_app(Windows(target_arch), APP_DIR, "$BUILD_DIR/$target_name.msix"; precompile, incremental)
end

if buildall || Sys.isapple()
    AppBundler.build_app(MacOS(target_arch), APP_DIR, "$BUILD_DIR/$target_name.dmg"; precompile, incremental)
end
