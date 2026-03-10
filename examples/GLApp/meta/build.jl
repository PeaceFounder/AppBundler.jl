using AppBundler

APP_DIR = dirname(@__DIR__)

config = AppBundler.parse_args(ARGS)

build_dir = config[:build_dir] 
@info "Build products will be created at $build_dir"

precompile = false
incremental = true
target_bundle = config[:target_bundle]
target_arch = config[:target_arch]
adhoc_signing = config[:adhoc_signing]
windowed = false
force = false

version = AppBundler.get_version(APP_DIR)
target_name = "glapp-$version-$(target_arch)"

spec = JuliaImgBundle(APP_DIR; precompile, incremental)

if :snap in target_bundle
    snap = Snap(APP_DIR; windowed)
    bundle(spec, snap, "$build_dir/$target_name.snap"; force, target_arch)
end

if :msix in target_bundle
    msix = MSIX(APP_DIR; windowed, 
                (adhoc_signing ? (; pfx_cert=nothing) : (;))...)
    bundle(spec, msix, "$build_dir/$target_name.msix"; force, target_arch)
end

if :dmg in target_bundle
    dmg = DMG(APP_DIR; windowed, 
              (adhoc_signing ? (; pfx_cert=nothing) : (;))...)
    bundle(spec, dmg, "$build_dir/$target_name.dmg"; force, target_arch)
end
