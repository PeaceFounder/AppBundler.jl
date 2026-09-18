using Test
import AppBundler.JuliaC: JuliaCBundle, get_juliac, juliac_shim
import AppBundler: stage, Snap, MSIX, DMG, bundle

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

spec = JuliaCBundle(project; trim = true, asset_spec)
build_dir = mktempdir()
#build_dir = joinpath(dirname(@__DIR__), "build")

if isfile(spec.juliac_cmd.exec[1])

    if Sys.islinux()
        snap = Snap(project; windowed = false)
        bundle(spec, snap, joinpath(build_dir, "cmdapp.snap"); force=true)
    elseif Sys.isapple()
        dmg = DMG(project; windowed = false, selfsign = true)
        bundle(spec, dmg, joinpath(build_dir, "cmdapp.dmg"); force=true)
    elseif Sys.iswindows()
        msix = MSIX(project; windowed = false, selfsign = true)
        bundle(spec, msix, joinpath(build_dir, "cmdappwin.msix"); force=true)
    else
        @warn "Nothing tested for JuliaC on this platform"
    end

else
    @warn "JuliaC tests are skipped because juliac can't be found in ~/.julia/juliac"
end
