using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap, MSIXPack
import AppBundler

using osslsigncode_jll
using AppBundler.OpenSSLLegacy: openssl

using SHA

include("utils.jl")

if isdir(joinpath(pkgdir(AppBundler), ".git"))
    @test AppBundler.commit_count(pkgdir(AppBundler)) > 0
end

# # ------------------------ MSIX -------------------

function verify_msix_signature(msix_file)
    # First try standard verification (likely to fail with self-signed certs)
        
    # Create temporary files
    sig_file = tempname() * ".sig"
    cert_file = tempname() * ".pem"
    
    # Extract the signature
    @info "Extracting signature..."
    run(`$(osslsigncode()) extract-signature -in $msix_file -out $sig_file`)
    
    # Extract the certificate from the signature
    @info "Extracting certificate from signature..."
    run(`$(openssl()) pkcs7 -inform DER -in $sig_file -print_certs -out $cert_file`)
    
    # Verify the MSIX using the extracted certificate as the trusted CA
    @info "Verifying with extracted certificate..."
    run(`$(osslsigncode()) verify -in $msix_file -CAfile $cert_file`)
    
    @info "Verification successful with extracted certificate"
    return
end

predicate = :JULIA_IMG_BUNDLE

@time @testset "MSIX bundling tests" begin

    msix = MSIX(joinpath(@__DIR__, "../examples/GtkApp"); selfsign=true, predicate)

    @test hash_stage() do dest
        stage(msix, dest)
        #AppBundler.MSIXPack.update_publisher_in_manifest(joinpath(dest, "AppxManifest.xml"), "AppBundler")
    end == "f0795381b99cddea7d98b7b52bf9264f82d733ab7443723d1f218ee74ba7f93a" #"2f2422ef39534041f56695e275441ab10835fc5e5d675cd5c40e058b5839cbc7"

    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.msix")
        bundle(msix, dest) do app_stage
            @info "The MSIX app stage is $app_stage"
            touch(joinpath(app_stage, "MRF_signal_Δθ_23_NTRs_500.mrd"))
        end

        verify_msix_signature(dest)

        MSIXPack.repack(dest, tempname(); pfx_path = msix.pfx_cert) # useful for debugging MSIX configuration issues

        AppBundler.MSIXPack.unpack(dest, stage_dir)
        rm(joinpath(stage_dir, "AppxSignature.p7x")) # Signatures are always nondeterministic

        # @test hash_file(joinpath(stage_dir, "AppxBlockMap.xml")) == "70ff6695ec913326f645c1cd30e48f75f57545ee4ae546db5843bf0779e6ee7e"
        rm(joinpath(stage_dir, "AppxBlockMap.xml")) # AppxBlockMap.xml has a slight nondeterminism

    end == "f0795381b99cddea7d98b7b52bf9264f82d733ab7443723d1f218ee74ba7f93a"
end

if Sys.isunix()

    # # ------------------- DMG -------------

    @time @testset "DMG bundling tests" begin

        dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = true, selfsign = true, predicate, main_redirect = true, arch = :x86_64)

        @test hash_stage() do dest
            stage(dmg, joinpath(dest, "GtkApp.app"); dsstore=true)
            AppBundler.DMGPack.replace_binary_with_hash(joinpath(dest, "GtkApp.app/Contents/MacOS/gtkapp"))
            rm("$dest/Applications")
        end == "a06201da07a673a2c3c1dbc13d85c3a72334e4b3e479df2322245a98ce14e838"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.dmg")
            bundle(dmg, dest) do app_stage
                @info "The DMG app stage is $app_stage"
            end
            
            if Sys.isapple()
                @info "Verifying integrity of the DMG archive"
                run(`hdiutil verify $dest`)
            end

            AppBundler.DMGPack.unpack(dest, stage_dir)

            if Sys.isapple()
                # This check is also important for stagging
                @info "Verifying that the application is correctly codesigned"
                run(`codesign --verify --deep --verbose=4 "$stage_dir/GtkApp.app"`)

                @info "Verifying if the application has hardened runtime enabled"
                io = IOBuffer()
                run(pipeline(`codesign -dvv $stage_dir/GtkApp.app`, stderr=io))
                output = String(take!(io))

                @test occursin(r"Timestamp=", output)
                @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
            end

            @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
            rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

        end == "a06201da07a673a2c3c1dbc13d85c3a72334e4b3e479df2322245a98ce14e838"


        if Sys.isapple()
            @test hash_stage() do stage_dir

                dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = false, selfsign = true, predicate, main_redirect = true, arch = :x86_64)
                dest = joinpath(mktempdir(), "gtkapp.dmg")
                bundle(dmg, dest) do app_stage
                    @info "The DMG app stage is $app_stage"
                end
                
                @info "Verifying integrity of the DMG archive"
                run(`hdiutil verify $dest`)

                @info "Verifying contents of DMG archive"
                mount_point = mount_dmg(dest)
                try
                    @info "Verifying that the application is correctly codesigned"                    
                    run(`codesign --verify --deep --strict --verbose=4 "$mount_point/GtkApp.app"`)

                    @info "Verifying if the application has hardened runtime enabled"
                    io = IOBuffer()
                    run(pipeline(`codesign -dvv $mount_point/GtkApp.app`, stderr=io))
                    output = String(take!(io))

                    @test occursin(r"Timestamp=", output)
                    @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
 
                    cp(mount_point, stage_dir; force=true)
                finally
                    unmount_dmg(mount_point)
                end

                @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
                rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

            end == "a06201da07a673a2c3c1dbc13d85c3a72334e4b3e479df2322245a98ce14e838"
        end
    end

    # # -------------------- SNAP -----------------

    @time @testset "Snap bundling tests" begin

        snap = Snap(joinpath(@__DIR__, "../examples/GtkApp"); predicate, configure_hook = nothing)

        @test hash_stage() do dest
            stage(snap, dest)
        end == "ed982e260a2dd4f2260d66d1337ad6eb725e42e817bddcb9bd9ed953539b8328"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.snap")
            bundle(snap, dest) do app_stage
                @info "The Snap app stage is $app_stage"
            end
            
            AppBundler.SnapPack.unpack(dest, stage_dir)    

        end == "ed982e260a2dd4f2260d66d1337ad6eb725e42e817bddcb9bd9ed953539b8328"
    end

end
