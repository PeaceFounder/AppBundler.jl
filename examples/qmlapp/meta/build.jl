using AppBundler

APP_DIR = dirname(@__DIR__)

config = AppBundler.parse_args(ARGS)

build_dir = config[:build_dir] 
@info "Build products will be created at $build_dir"

precompile = config[:precompile]
incremental = config[:incremental]
target_platforms = config[:target_platforms]
target_arch = config[:target_arch]
adhoc_signing = config[:adhoc_signing]
sysimg_packages = ["QMLApp"]

version = AppBundler.get_version(APP_DIR)
target_name = "qmlapp-$version-$(target_arch)"

if :linux in target_platforms
    AppBundler.build_app(Linux(target_arch), APP_DIR, "$build_dir/$target_name.snap"; precompile, incremental, sysimg_packages)
end

if :windows in target_platforms
    AppBundler.build_app(Windows(target_arch), APP_DIR, "$build_dir/$target_name.msix"; precompile, incremental, adhoc_signing, sysimg_packages)
end

if :macos in target_platforms
    AppBundler.build_app(MacOS(target_arch), APP_DIR, "$build_dir/$target_name.dmg"; precompile, incremental, adhoc_signing, sysimg_packages)
end
