using AppBundler
using Test

app_dir = joinpath(dirname(@__DIR__), "examples/glapp")

include("utils.jl")

try
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    AppBundler.generate_signing_certificates(; root = app_dir, force = true)

    build_dir = mktempdir()
    push!(ARGS, "--compiled-modules=no")
    push!(ARGS, "--build-dir=$build_dir")
    @eval include("../examples/glapp/meta/build.jl")

    if Sys.isapple()

        dmg_path = joinpath(build_dir, target_name * ".dmg")
        
        @info "Verifying integrity of DMG bundle"
        run(`hdiutil verify $dmg_path`)

        mount_point = mount_dmg(dmg_path)
        try
            @info "Verifying that the application is correctly codesigned"        
            # Need to inspect the strict option
            #run(`codesign --verify --deep --strict --verbose=4 "$mount_point/glapp.app"`)
            run(`codesign --verify --deep --verbose=4 "$mount_point/glapp.app"`)

            @info "Verifying if the application has hardened runtime enabled"
            io = IOBuffer()
            run(pipeline(`codesign -dvv "$mount_point/glapp.app"`, stderr=io))
            output = String(take!(io))

            @test occursin(r"Timestamp=", output)
            @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
        finally
            unmount_dmg(mount_point)
        end
    end
    
finally
    # cleanup
    empty!(ARGS)
    rm(joinpath(app_dir, "meta/msix/certificate.pfx"); force = true)
    rm(joinpath(app_dir, "meta/dmg/certificate.pfx"); force = true)
    ENV["MACOS_PFX_PASSWORD"] = ""
    ENV["WINDOWS_PFX_PASSWORD"] = ""
end
