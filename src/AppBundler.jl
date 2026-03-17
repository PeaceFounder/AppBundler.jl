module AppBundler

using Scratch
import Pkg.BinaryPlatforms: Linux, MacOS, Windows
import Pkg

DOWNLOAD_CACHE = ""

julia_tarballs() = joinpath(DOWNLOAD_CACHE, "julia-tarballs")
artifacts_cache() = joinpath(DOWNLOAD_CACHE, "artifacts")

"""
    BuildSpec

Abstract specification for building and packaging applications.

Concrete subtypes:
- [`JuliaImgBundle`](@ref): Julia application with full runtime
- [`JuliacBundle`](@ref): Standalone executable compiled with JuliaC
"""
abstract type BuildSpec end

function stage end

include("DMG/DSStore.jl")
include("DMG/HFS.jl")
include("DMG/DMGPack.jl")

include("Snap/SnapPack.jl")

include("MSIX/OpenSSLLegacy.jl")
include("MSIX/MSIXPack.jl")
include("MSIX/MSIXIcons.jl")
include("MSIX/WinSubsystem.jl")

include("bundlers/Resources.jl") # JuliaC needs assets and pkgorigins_index which is shared between JuliaImg and JuliaC
include("bundlers/JuliaImg/JuliaImg.jl") 
include("bundlers/JuliaC.jl")

using .JuliaImg: install
using .JuliaImg.Resources: merge_directories#, install

include("config.jl")
include("utils.jl")
include("bundle.jl")
include("recipes.jl") 

bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end

function main_build(ARGS; sources_dir)

    config = parse_args(ARGS)

    target_arch = config[:target_arch]
    target_bundle = config[:target_bundle]
    build_dir = config[:build_dir]
    selfsign = config[:selfsign]
    compress = config[:compress]
    windowed = config[:windowed]
    overwrite_target = config[:overwrite_target]
    password = config[:password]

    bundler = @load_preference("bundler")

    if bundler == "juliaimg"

        if @load_preference("juliaimg_selective_assets")
            remove_sources = true
            asset_spec = Resources.extract_asset_spec(sources_dir)
        else
            remove_sources = false
            asset_spec = Dict{Symbol, Vector{String}}()
        end

        spec = JuliaImgBundle(sources_dir; 
                              precompile = @load_preference("juliaimg_precompile"), 
                              incremental = @load_preference("juliaimg_incremental"),
                              sysimg_packages = @load_preference("juliaimg_sysimg"),
                              remove_sources,
                              asset_spec
                              ) 

    elseif bundler == "juliac"

        asset_spec = Resources.extract_asset_spec(sources_dir)
        spec = JuliaCBundle(sources_dir; trim = @load_preference("juliac_trim"), asset_spec) 

    else

        error("Got unsupported bundler type $bundler")

    end

    function target_name(parameters)
        if isnothing(config[:target_name])
            version = parameters["APP_VERSION"]
            app_name = parameters["APP_NAME"]
            return "$(app_name)-$version-$(target_arch)"
        else
            return config[:target_name]
        end
    end

    if :msix == target_bundle

        msix = MSIX(sources_dir; windowed, selfsign)
        
        if selfsign
            password = ""
        else
            if isnothing(msix.pfx_cert)
                error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
            end

            if isnothing(password)
                print("Type in certificate password:")
                password = readline() |> strip
            end
        end

        target_path = joinpath(build_dir, target_name(msix.parameters))
        bundle(spec, msix, compress ? "$target_path.msix" : target_path; force = overwrite_target, target_arch, password)

    elseif :dmg == target_bundle

        dmg = DMG(sources_dir; windowed, selfsign)


        if selfsign
            password = ""
        else
            if isnothing(dmg.pfx_cert)
                error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
            end

            if isnothing(password)
                print("Type in certificate password:")
                password = strip(readline())
            end
        end

        target_path = joinpath(build_dir, target_name(dmg.parameters))
        bundle(spec, dmg, compress ? "$target_path.dmg" : target_path; force = overwrite_target, target_arch, password)

    elseif :snap == target_bundle

        snap = Snap(sources_dir; windowed)
        target_path = joinpath(build_dir, target_name(snap.parameters))
        bundle(spec, snap, compress ? "$target_path.snap" : target_path; force = overwrite_target, target_arch)

    else
        error("Got unsupported bundle type $target_bundle")
    end

    return
end

function (@main)(ARGS)

    if ARGS[1] == "build"

        old_project = Base.ACTIVE_PROJECT[]
        push!(Base.LOAD_PATH, pkgdir(AppBundler)) # needed for reading LocalPreferences.toml when AppBundler is loaded as project

        try
            Base.ACTIVE_PROJECT[] = joinpath(realpath(ARGS[2]))
            main_build(ARGS[3:end]; sources_dir = realpath(ARGS[2]))
        finally
            pop!(Base.LOAD_PATH)
            Base.ACTIVE_PROJECT[] = old_project
        end

    elseif ARGS[1] == "--help"
        println("Use the command as `appbundler [build|instantiate] [args]`.")

    else

        error("Got unsupported command $(ARGS[1]). See `--help` for available commands.")

    end

    return 0
end


export JuliaImgBundle, JuliaCBundle, DMG, MSIX, Snap, bundle, stage
export main 


end
