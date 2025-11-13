using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap
import AppBundler

using osslsigncode_jll
using OpenSSL_jll

using SHA

include("utils.jl")

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

@time @testset "MSIX bundling tests" begin

    msix = MSIX(joinpath(@__DIR__, "../examples/gtkapp"))

    @test hash_stage() do dest
        stage(msix, dest)
        AppBundler.MSIXPack.update_publisher_in_manifest(joinpath(dest, "AppxManifest.xml"), "AppBundler")
    end == "1fcfcd7a0c13a465b0f4c530770291db6a0e9424853cde28727668c3f643eeeb"

    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.msix")
        bundle(msix, dest) do app_stage
            @info "The MSIX app stage is $app_stage"
            touch(joinpath(app_stage, "MRF_signal_Δθ_23_NTRs_500.mrd"))
        end

        verify_msix_signature(dest)

        AppBundler.MSIXPack.unpack(dest, stage_dir)
        rm(joinpath(stage_dir, "AppxSignature.p7x")) # Signatures are always nondeterministic

        AppBundler.MSIXPack.update_publisher_in_manifest(joinpath(stage_dir, "AppxManifest.xml"), "AppBundler")
        
        # @test hash_file(joinpath(stage_dir, "AppxBlockMap.xml")) == "70ff6695ec913326f645c1cd30e48f75f57545ee4ae546db5843bf0779e6ee7e"
        rm(joinpath(stage_dir, "AppxBlockMap.xml")) # AppxBlockMap.xml has a slight nondeterminism

    end == "1fcfcd7a0c13a465b0f4c530770291db6a0e9424853cde28727668c3f643eeeb"
end

if Sys.isunix()

    # ------------------- DMG -------------

    @time @testset "DMG bundling tests" begin

        dmg = DMG(joinpath(@__DIR__, "../examples/gtkapp"); hfsplus = true)

        @test hash_stage() do dest
            stage(dmg, joinpath(dest, "gtkapp.app"); dsstore=true, main_redirect=true)
            AppBundler.DMGPack.replace_binary_with_hash(joinpath(dest, "gtkapp.app/Contents/MacOS/gtkapp"))
            rm("$dest/Applications")
        end == "475c21a0947fe2e7a217581982ea574854da395ae78e06e341d646565fca501a"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.dmg")
            bundle(dmg, dest; main_redirect=true) do app_stage
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
                run(`codesign --verify --deep --verbose=4 "$stage_dir/gtkapp.app"`)

                @info "Verifying if the application has hardened runtime enabled"
                io = IOBuffer()
                run(pipeline(`codesign -dvv $stage_dir/gtkapp.app`, stderr=io))
                output = String(take!(io))

                @test occursin(r"Timestamp=", output)
                @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
            end

            @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "gtkapp.app/Contents/MacOS/gtkapp"))
            rm("$stage_dir/gtkapp.app/Contents/_CodeSignature"; recursive=true)

        end == "475c21a0947fe2e7a217581982ea574854da395ae78e06e341d646565fca501a"


        if Sys.isapple()
            @test hash_stage() do stage_dir

                dmg = DMG(joinpath(@__DIR__, "../examples/gtkapp"); hfsplus = false)
                dest = joinpath(mktempdir(), "gtkapp.dmg")
                bundle(dmg, dest; main_redirect=true) do app_stage
                    @info "The DMG app stage is $app_stage"
                end
                
                @info "Verifying integrity of the DMG archive"
                run(`hdiutil verify $dest`)

                @info "Verifying contents of DMG archive"
                mount_point = mount_dmg(dest)
                try
                    @info "Verifying that the application is correctly codesigned"                    
                    run(`codesign --verify --deep --strict --verbose=4 "$mount_point/gtkapp.app"`)

                    @info "Verifying if the application has hardened runtime enabled"
                    io = IOBuffer()
                    run(pipeline(`codesign -dvv $mount_point/gtkapp.app`, stderr=io))
                    output = String(take!(io))

                    @test occursin(r"Timestamp=", output)
                    @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
 
                    cp(mount_point, stage_dir; force=true)
                finally
                    unmount_dmg(mount_point)
                end

                @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "gtkapp.app/Contents/MacOS/gtkapp"))
                rm("$stage_dir/gtkapp.app/Contents/_CodeSignature"; recursive=true)

            end == "475c21a0947fe2e7a217581982ea574854da395ae78e06e341d646565fca501a"
        end
    end

    # # -------------------- SNAP -----------------

    @time @testset "Snap bundling tests" begin

        snap = Snap(joinpath(@__DIR__, "../examples/gtkapp"))

        @test hash_stage() do dest
            stage(snap, dest; install_configure=true)
        end == "c4a970b79da0db6c5bfff1947c12ee119d0c0a2b44f3d153d78fd56ad2252d12"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.snap")
            bundle(snap, dest; install_configure=true) do app_stage
                @info "The Snap app stage is $app_stage"
            end
            
            AppBundler.SnapPack.unpack(dest, stage_dir)    

        end == "c4a970b79da0db6c5bfff1947c12ee119d0c0a2b44f3d153d78fd56ad2252d12"
    end

end
