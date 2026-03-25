import AppBundler.JuliaC: JuliaCBundle
import AppBundler: stage, Snap, MSIX, DMG, bundle

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
