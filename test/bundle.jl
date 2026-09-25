using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap, MSIXPack, AppImage, DMGPack
import AppBundler

using osslsigncode_jll
using OpenSSL_CLI_jll: openssl

using SHA

include("utils.jl")

if isdir(joinpath(pkgdir(AppBundler), ".git")) && Sys.isunix()
    @test AppBundler.commit_count(pkgdir(AppBundler)) > 0
end

const APP_DIR = joinpath(@__DIR__, "../examples/GtkApp")

# ------------------------ MSIX -------------------

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

# ------------------------ DMG -------------------

function build_dmg(dmg)
    dest = joinpath(mktempdir(), "gtkapp.dmg")
    bundle(dmg, dest; verbose = true) do app_stage
        @info "The DMG app stage is $app_stage"
    end
    if Sys.isapple()
        @info "Verifying integrity of the DMG archive"
        run(`hdiutil verify $dest`)
    end
    return dest
end

function verify_codesign(app; strict = false)
    @info "Verifying that the application is correctly codesigned"
    strict_flag = strict ? ["--strict"] : String[]
    run(`codesign --verify --deep $strict_flag --verbose=4 $app`)

    @info "Verifying if the application has hardened runtime enabled"
    io = IOBuffer()
    run(pipeline(`codesign -dvv $app`, stderr = io))
    output = String(take!(io))

    @test occursin(r"Timestamp=", output)
    @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
end

function normalize_app!(stage_dir; signed = true)
    app = joinpath(stage_dir, "GtkApp.app")
    replace_binary_with_hash(joinpath(app, "Contents/MacOS/gtkapp"))
    signed && rm(joinpath(app, "Contents/_CodeSignature"); recursive = true)
end

predicate = "juliaimg"

@time @testset "MSIX bundling tests" begin

    msix = MSIX(APP_DIR; selfsign=true, predicate, windowed = true)

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

        gtkapp_dmg(backend) = DMG(APP_DIR; backend, selfsign = true, predicate, arch = :x86_64, windowed = false)

        @test hash_stage() do dest
            stage(gtkapp_dmg(DMGPack.XorrisoBackend(true)), joinpath(dest, "GtkApp.app"); dsstore = true)
            normalize_app!(dest; signed = false)
            rm(joinpath(dest, "Applications"))
        end == "b754eb61b047f86823b51c62f111ac2c4ca7cbf3e8392de20ec8ecedda0bb898"

        backends = [DMGPack.XorrisoBackend(true), DMGPack.HFSPlusBackend(0.02)]

        @testset "$backend" for backend in backends

            dmg = gtkapp_dmg(backend)
            dmg_path = build_dmg(dmg)

            Sys.isapple() && run(`hdiutil verify $dmg_path`)

            @test hash_stage() do stage_dir
                AppBundler.DMGPack.unpack(dmg_path, stage_dir; verbose = true)
                Sys.isapple() && verify_codesign(joinpath(stage_dir, "GtkApp.app"); strict = true)
                normalize_app!(stage_dir)
            end == "b754eb61b047f86823b51c62f111ac2c4ca7cbf3e8392de20ec8ecedda0bb898"
        end
    end

    # -------------------- SNAP -----------------

    @time @testset "Snap bundling tests" begin

        snap = Snap(APP_DIR; predicate, configure_hook = nothing, windowed = true)

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

    appimage = AppImage(APP_DIR; predicate, windowed = false, arch = Sys.ARCH)


    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.appimage")

        bundle(appimage, dest) do app_stage
            @info "The AppImage app stage is $app_stage"
        end

        AppBundler.AppImagePack.unpack(dest, stage_dir)    

    end == "65fa67c7cbb11b0087fe759b87c90023a70261f20ea3db6c86b50828d4252a55"

end
