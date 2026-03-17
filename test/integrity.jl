using AppBundler
using Test

@test AppBundler.normalize_args(["--password=dfdfsdf"]) == ["--password", "dfdfsdf"]
@test AppBundler.normalize_args(["--password=\"dfdfsdf\""]) == ["--password", "dfdfsdf"]

app_dir = joinpath(dirname(@__DIR__), "examples/GLApp")
build_dir = mktempdir()
target_name = "glapp"
target_bundle = Sys.islinux() ? "snap" : Sys.isapple() ? "dmg" : Sys.iswindows() ? "msix" : error("Bundling for current platform is unsupported")

include("utils.jl")

try
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    (; password_macos, password_windows) = AppBundler.generate_signing_certificates(; root = app_dir, force = true)

    args = ["build", app_dir, "--build-dir=$build_dir", "--target-name=glapp", "--target-bundle=$target_bundle"]

    if target_bundle == "dmg"
        push!(args, "--password=$password_macos") # ToDo: add quates here becuase password may incidentally generate `--` Although base64 encoding may protect from such situation here. Still relevant.
    elseif target_bundle == "msix"
        push!(args, "--password=$password_windows")
    end

    AppBundler.main(args)
    
    if Sys.isapple()

        dmg_path = joinpath(build_dir, target_name * ".dmg")
        
        @info "Verifying integrity of DMG bundle"
        run(`hdiutil verify $dmg_path`)

        mount_point = mount_dmg(dmg_path)
        try
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
        finally
            unmount_dmg(mount_point)
        end
    end
    
finally
    # cleanup
    rm(joinpath(app_dir, "meta/msix/certificate.pfx"); force = true)
    rm(joinpath(app_dir, "meta/dmg/certificate.pfx"); force = true)
    rm(joinpath(app_dir, ".github"); force = true, recursive = true)
end


# JuliaC example
app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
AppBundler.main(["build", app_dir, "--selfsign"])
