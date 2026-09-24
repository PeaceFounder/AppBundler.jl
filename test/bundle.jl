using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap, MSIXPack, AppImage
import AppBundler

using osslsigncode_jll
using OpenSSL_CLI_jll: openssl

using SHA

include("utils.jl")

if isdir(joinpath(pkgdir(AppBundler), ".git")) && Sys.isunix()
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

predicate = "juliaimg"

@time @testset "MSIX bundling tests" begin

    msix = MSIX(joinpath(@__DIR__, "../examples/GtkApp"); selfsign=true, predicate, windowed = true)

    @test hash_stage() do dest
        stage(msix, dest)
    end == "268e73a3c6bcf2043a8fad59af54a2a8885322cf1da35c8a6f0d64be5c1c8dbc"

    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.msix")
        bundle(msix, dest) do app_stage
            @info "The MSIX app stage is $app_stage"
            touch(joinpath(app_stage, "MRF_signal_Δθ_23_NTRs_500.mrd"))
        end

        verify_msix_signature(dest)

        MSIXPack.repack(dest, tempname()) # useful for debugging MSIX configuration issues

        AppBundler.MSIXPack.unpack(dest, stage_dir)

        rm(joinpath(stage_dir, "AppxSignature.p7x")) # Signatures are always nondeterministic

        # @test hash_file(joinpath(stage_dir, "AppxBlockMap.xml")) == "70ff6695ec913326f645c1cd30e48f75f57545ee4ae546db5843bf0779e6ee7e"
        rm(joinpath(stage_dir, "AppxBlockMap.xml")) # AppxBlockMap.xml has a slight nondeterminism

        msix2exe = AppBundler.MSIX2EXE(joinpath(@__DIR__, "../examples/GtkApp"))
        AppBundler.repack(dest, msix2exe, join((dest, ".exe")))

    end == "268e73a3c6bcf2043a8fad59af54a2a8885322cf1da35c8a6f0d64be5c1c8dbc"
end

if Sys.isunix()

    # ------------------- DMG -------------

    @time @testset "DMG bundling tests" begin

        dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = true, selfsign = true, predicate, arch = :x86_64, windowed = false)

        @test hash_stage() do dest
            stage(dmg, joinpath(dest, "GtkApp.app"); dsstore=true)
            AppBundler.DMGPack.replace_binary_with_hash(joinpath(dest, "GtkApp.app/Contents/MacOS/gtkapp"))
            rm("$dest/Applications")

        end == "b754eb61b047f86823b51c62f111ac2c4ca7cbf3e8392de20ec8ecedda0bb898" 

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

            AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
            rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

        end == "b754eb61b047f86823b51c62f111ac2c4ca7cbf3e8392de20ec8ecedda0bb898"


        if Sys.isapple()
            @test hash_stage() do stage_dir

                dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = false, selfsign = true, predicate, arch = :x86_64, windowed = false)
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

                AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
                rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

            end == "b754eb61b047f86823b51c62f111ac2c4ca7cbf3e8392de20ec8ecedda0bb898"
        end
    end

    # -------------------- SNAP -----------------

    @time @testset "Snap bundling tests" begin

        snap = Snap(joinpath(@__DIR__, "../examples/GtkApp"); predicate, configure_hook = nothing, windowed = true)

        @test hash_stage() do dest
            stage(snap, dest)
        end == "cf6f6df039acd7ddc9900dd29d69ea5427d3e270bba0c72e77bd617d7b693f2c"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.snap")
            bundle(snap, dest) do app_stage
                @info "The Snap app stage is $app_stage"
            end
            
            AppBundler.SnapPack.unpack(dest, stage_dir)    

        end == "cf6f6df039acd7ddc9900dd29d69ea5427d3e270bba0c72e77bd617d7b693f2c"
    end


    # -------------------- AppImage -----------------

    appimage = AppImage(joinpath(@__DIR__, "../examples/GtkApp"); predicate, windowed = false, arch = Sys.ARCH)


    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.appimage")

        bundle(appimage, dest) do app_stage
            @info "The AppImage app stage is $app_stage"
        end

        AppBundler.AppImagePack.unpack(dest, stage_dir)    

    end == "65fa67c7cbb11b0087fe759b87c90023a70261f20ea3db6c86b50828d4252a55"

end
