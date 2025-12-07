# MANUAL TESTS: Before every major release, manually verify that produced bundles 
# are functional on each platform. Small configuration errors in startup scripts or 
# missing post-configuration steps can silently break bundles without failing builds.

import AppBundler: Snap, MSIX, DMG, bundle, JuliaAppBundle, JuliaCBundle

build_dir = joinpath(dirname(@__DIR__), "build")
mkpath(build_dir)
force = true

let
    project = joinpath(dirname(@__DIR__), "examples/modjulia")
    spec = JuliaAppBundle(project; incremental = true, precompile = false)
    target_name = "modjulia_uncompiled"
    windowed = false

    if Sys.islinux()
        snap = Snap(project; windowed)
        bundle(spec, snap, joinpath(build_dir, "$target_name.snap"); force)
    end

    if Sys.isapple()
        dmg = DMG(project; windowed)
        bundle(spec, dmg, joinpath(build_dir, "$target_name.dmg"); force)
    end

    if Sys.iswindows()
        msix = MSIX(project; windowed)
        bundle(spec, msix, joinpath(build_dir, "$target_name.msix"); force)
    end
end

let
    project = joinpath(dirname(@__DIR__), "examples/modjulia")
    spec = JuliaAppBundle(project; sysimg_packages = ["Mods"])
    target_name = "modjulia_sysimg"
    windowed = false

    if Sys.islinux()
        snap = Snap(project; windowed)
        bundle(spec, snap, joinpath(build_dir, "$target_name.snap"); force)
    end

    if Sys.isapple()
        dmg = DMG(project; windowed)
        bundle(spec, dmg, joinpath(build_dir, "$target_name.dmg"); force)
    end

    if Sys.iswindows()
        msix = MSIX(project; windowed)
        bundle(spec, msix, joinpath(build_dir, "$target_name.msix"); force)
    end
end

let
    asset_spec = Dict{Symbol, Vector{String}}(
        :QMLApp => ["src/App.qml"]
    )

    project = joinpath(dirname(@__DIR__), "examples/QMLApp")
    spec = JuliaAppBundle(project; sysimg_packages = ["QMLApp"], remove_sources = true, asset_rpath = "assets", asset_spec)
    target_name = "qmlapp_sysimg"
    windowed = true

    if Sys.islinux()
        snap = Snap(project; windowed)
        bundle(spec, snap, joinpath(build_dir, "$target_name.snap"); force)
    end

    if Sys.isapple()
        dmg = DMG(project; windowed)
        bundle(spec, dmg, joinpath(build_dir, "$target_name.dmg"); force)
    end

    if Sys.iswindows()
        msix = MSIX(project; windowed)
        bundle(spec, msix, joinpath(build_dir, "$target_name.msix"); force)
    end
end

let
    project = joinpath(dirname(@__DIR__), "examples/CmdApp")
    spec = JuliaCBundle(project; trim = true)
    target_name = "cmdapp_juliac"
    windowed = false

    if Sys.islinux()
        snap = Snap(project; windowed)
        bundle(spec, snap, joinpath(build_dir, "$target_name.snap"); force)
    end

    if Sys.isapple()
        dmg = DMG(project; windowed)
        bundle(spec, dmg, joinpath(build_dir, "$target_name.dmg"); force)
    end

    if Sys.iswindows()
        msix = MSIX(project; windowed)
        bundle(spec, msix, joinpath(build_dir, "$target_name.msix"); force)
    end
end

let
    project = joinpath(dirname(@__DIR__), "examples/QMLApp")
    spec = JuliaCBundle(project; trim = false)
    target_name = "qmlapp_juliac"
    windowed = true

    if Sys.islinux()
        snap = Snap(project; windowed)
        bundle(spec, snap, joinpath(build_dir, "$target_name.snap"); force)
    end

    if Sys.isapple()
        dmg = DMG(project; windowed) #sandboxed_runtime=true
        bundle(spec, dmg, joinpath(build_dir, "$target_name.dmg"); force)
    end

    if Sys.iswindows()
        msix = MSIX(project; windowed)
        bundle(spec, msix, joinpath(build_dir, "$target_name.msix"); force)
    end
end
