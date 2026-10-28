using AppBundler
using Test

const EXAMPLE_DIR = joinpath(pkgdir(AppBundler), "examples", "GLApp")

function fresh_project()
    project = joinpath(mktempdir(), "GLApp")
    cp(EXAMPLE_DIR, project)
    rm(joinpath(project, "meta"); recursive = true, force = true)
    return project
end

app_dir = fresh_project()
build_dir = mktempdir()
target_name = "glapp"
target_bundle = Sys.islinux() ? "snap" : Sys.isapple() ? "dmg" : Sys.iswindows() ? "msix" : error("Bundling for current platform is unsupported")

include("utils.jl")

args = ["build", app_dir, "--build-dir=$build_dir", "--target-name=glapp", "--target-bundle=$target_bundle", "-Djuliaimg.precompile=false", "-Dwindowed=true", "-Dmsix.bootstrapper=true"]

AppBundler.main(["inline", app_dir, "LocalPreferences.toml", "-Djuliaimg.precompile=false"])


AppBundler.main(["inline", app_dir, ".github/workflows/Release.yml"])

if target_bundle == "snap"
    AppBundler.main(["inline", app_dir, "meta/snap/icon.png"])
elseif target_bundle == "dmg"
    AppBundler.main(["inline", app_dir, "meta/dmg/icon.icns"])
    password = AppBundler.main_inline(app_dir, "meta/dmg/certificate.pfx", String[])
    push!(args, "--password", password) 
elseif target_bundle == "msix"
    AppBundler.main(["inline", app_dir, "meta/msix/Assets"])
    password = AppBundler.main_inline(app_dir, "meta/msix/certificate.pfx", String[])
    push!(args, "--password", password) 
end

AppBundler.main(args)

if Sys.isapple()

    dmg_path = joinpath(build_dir, target_name * ".dmg")
    
    @info "Verifying integrity of DMG bundle"
    run(`hdiutil verify $dmg_path`)

    with_mounted_dmg(dmg_path) do mount_point
        @info "Verifying that the application is correctly codesigned"        
        # Need to inspect the strict option
        #run(`codesign --verify --deep --strict --verbose=4 "$mount_point/glapp.app"`)
        run(`codesign --verify --deep --verbose=4 "$mount_point/GLApp.app"`)

        @info "Verifying if the application has hardened runtime enabled"
        io = IOBuffer()
        run(pipeline(`codesign -dvv "$mount_point/GLApp.app"`, stderr=io))
        output = String(take!(io))

        @test occursin(r"Timestamp=", output)
        @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
    end
end

# # JuliaC example
# app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
# AppBundler.main(["build", app_dir, "--selfsign"])

# if Sys.islinux()
#     app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
#     AppBundler.main(["build", app_dir, "--selfsign", "--target-bundle=appimage"])
# end
