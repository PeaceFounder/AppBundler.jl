using Test
import AppBundler.JuliaC: JuliaCBundle, get_juliac, juliac_shim
import AppBundler: stage, Snap, MSIX, DMG, AppImage, MSIX2EXE, bundle, repack

# If we set environment variable JuliaC 
withenv("JULIAC"=>"juliac_backup") do
    @test get_juliac() == `juliac_backup`
end

# If we are with the project that does not have 
old = Base.ACTIVE_PROJECT[]
try 
    Base.ACTIVE_PROJECT[] = nothing
    shim = juliac_shim()

    if isnothing(shim)
        @test_throws ErrorException get_juliac()
    else
        @test get_juliac() == Cmd([shim])
    end

    Base.ACTIVE_PROJECT[] = joinpath(dirname(@__DIR__), "examples/CmdApp/meta")
    @test get_juliac()[1] == Base.julia_cmd()[1]
finally
    Base.ACTIVE_PROJECT[] = old
end

project = joinpath(dirname(@__DIR__), "examples/CmdApp")

asset_spec = Dict{Symbol, Vector{String}}(
    :AppEnv => ["LICENSE"]
)

#build_dir = mktempdir()
build_dir = joinpath(dirname(@__DIR__), "build")

try
    spec = JuliaCBundle(project; trim = true, asset_spec)
    predicate = "juliac"

    if Sys.islinux()
        snap = Snap(project; windowed = false, predicate)
        bundle(spec, snap, joinpath(build_dir, "cmdapp-juliac.snap"); force=true)

        appimage = AppImage(project; windowed = false, predicate)
        #appimage = AppImage(project; windowed = false, predicate, runtime = joinpath(dirname(@__DIR__), "build/AppImageRuntime.v2025.11.8.aarch64-linux-gnu/bin/runtime"))
        #appimage = AppImage(project; windowed = false, predicate, runtime = joinpath(dirname(@__DIR__), "build/AppImageRuntime.v2025.11.8.aarch64-linux-musl/bin/runtime"))
        bundle(spec, appimage, joinpath(build_dir, "cmdapp-juliac.appimage"); force=true)
    elseif Sys.isapple()
        dmg = DMG(project; windowed = false, selfsign = true, predicate)
        bundle(spec, dmg, joinpath(build_dir, "cmdapp-juliac.dmg"); force=true)
    elseif Sys.iswindows()
        msix = MSIX(project; windowed = false, selfsign = true, predicate)
        msix_path = joinpath(build_dir, "cmdapp-juliac.msix")
        bundle(spec, msix, msix_path; force=true)

        exe_spec = MSIX2EXE(project; windowed = false)
        exe_path = joinpath(build_dir, "cmdapp-juliac.exe")
        repack(msix_path, exe_spec, exe_path)
    else
        @warn "Nothing tested for JuliaC on this platform"
    end

catch
    @warn "JuliaC tests are skipped because juliac can't be found in ~/.julia/juliac"
end
