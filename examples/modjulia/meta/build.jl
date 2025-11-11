using AppBundler

APP_DIR = dirname(@__DIR__)

config = AppBundler.parse_args(ARGS)

build_dir = config[:build_dir] 
@info "Build products will be created at $build_dir"

precompile = config[:precompile]
incremental = true # config[:incremental]
target_platforms = config[:target_platforms]
target_arch = config[:target_arch]
adhoc_signing = config[:adhoc_signing]
windowed = false

version = AppBundler.get_version(APP_DIR)
target_name = "modjulia-$version-$(target_arch)"

if :linux in target_platforms
    AppBundler.build_app(Linux(target_arch), APP_DIR, "$build_dir/$target_name.snap"; precompile, incremental, windowed)
end

if :windows in target_platforms
    AppBundler.build_app(Windows(target_arch), APP_DIR, "$build_dir/$target_name.msix"; precompile, incremental, adhoc_signing, windowed)
end

if :macos in target_platforms
    rm("$build_dir/$target_name.app", force=true, recursive=true)
    AppBundler.build_app(MacOS(target_arch), APP_DIR, "$build_dir/$target_name"; precompile, incremental, adhoc_signing, windowed)
    mv("$build_dir/$target_name", "$build_dir/$target_name.app")
end
