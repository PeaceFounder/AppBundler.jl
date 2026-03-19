using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap, MSIXPack
import AppBundler

using osslsigncode_jll
using AppBundler.OpenSSLLegacy: openssl

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
    end == "4351935f32e1b0036bbf31c0f496b5734dd6a9496e8a0005675a097233a6d07e"

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

    end == "4351935f32e1b0036bbf31c0f496b5734dd6a9496e8a0005675a097233a6d07e"
end

# if Sys.isunix()

#     # ------------------- DMG -------------

#     @time @testset "DMG bundling tests" begin

#         dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = true, selfsign = true, predicate, arch = :x86_64)

#         @test hash_stage() do dest
#             stage(dmg, joinpath(dest, "GtkApp.app"); dsstore=true)
#             AppBundler.DMGPack.replace_binary_with_hash(joinpath(dest, "GtkApp.app/Contents/MacOS/gtkapp"))
#             rm("$dest/Applications")
#         end == "340323df33e9f976003cb5b8e6059f3a09226c6eb93d489a406feae39ef3345d" 

#         @test hash_stage() do stage_dir

#             dest = joinpath(mktempdir(), "gtkapp.dmg")
#             bundle(dmg, dest) do app_stage
#                 @info "The DMG app stage is $app_stage"
#             end
            
#             if Sys.isapple()
#                 @info "Verifying integrity of the DMG archive"
#                 run(`hdiutil verify $dest`)
#             end

#             AppBundler.DMGPack.unpack(dest, stage_dir)

#             if Sys.isapple()
#                 # This check is also important for stagging
#                 @info "Verifying that the application is correctly codesigned"
#                 run(`codesign --verify --deep --verbose=4 "$stage_dir/GtkApp.app"`)

#                 @info "Verifying if the application has hardened runtime enabled"
#                 io = IOBuffer()
#                 run(pipeline(`codesign -dvv $stage_dir/GtkApp.app`, stderr=io))
#                 output = String(take!(io))

#                 @test occursin(r"Timestamp=", output)
#                 @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
#             end

#             @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
#             rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

#         end == "340323df33e9f976003cb5b8e6059f3a09226c6eb93d489a406feae39ef3345d"


#         if Sys.isapple()
#             @test hash_stage() do stage_dir

#                 dmg = DMG(joinpath(@__DIR__, "../examples/GtkApp"); hfsplus = false, selfsign = true, predicate, arch = :x86_64)
#                 dest = joinpath(mktempdir(), "gtkapp.dmg")
#                 bundle(dmg, dest) do app_stage
#                     @info "The DMG app stage is $app_stage"
#                 end
                
#                 @info "Verifying integrity of the DMG archive"
#                 run(`hdiutil verify $dest`)

#                 @info "Verifying contents of DMG archive"
#                 mount_point = mount_dmg(dest)
#                 try
#                     @info "Verifying that the application is correctly codesigned"                    
#                     run(`codesign --verify --deep --strict --verbose=4 "$mount_point/GtkApp.app"`)

#                     @info "Verifying if the application has hardened runtime enabled"
#                     io = IOBuffer()
#                     run(pipeline(`codesign -dvv $mount_point/GtkApp.app`, stderr=io))
#                     output = String(take!(io))

#                     @test occursin(r"Timestamp=", output)
#                     @test occursin(r"flags=0x[0-9a-f]+\(runtime\)", output)
 
#                     cp(mount_point, stage_dir; force=true)
#                 finally
#                     unmount_dmg(mount_point)
#                 end

#                 @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "GtkApp.app/Contents/MacOS/gtkapp"))
#                 rm("$stage_dir/GtkApp.app/Contents/_CodeSignature"; recursive=true)

#             end == "340323df33e9f976003cb5b8e6059f3a09226c6eb93d489a406feae39ef3345d"
#         end
#     end

#     # -------------------- SNAP -----------------

#     @time @testset "Snap bundling tests" begin

#         snap = Snap(joinpath(@__DIR__, "../examples/GtkApp"); predicate, configure_hook = nothing, windowed = true)

#         @test hash_stage() do dest
#             stage(snap, dest)
#         end == "f64997788eca9a5d020c4fe73921d4085fc07ea2266b1401276162efd4695678"

#         @test hash_stage() do stage_dir

#             dest = joinpath(mktempdir(), "gtkapp.snap")
#             bundle(snap, dest) do app_stage
#                 @info "The Snap app stage is $app_stage"
#             end
            
#             AppBundler.SnapPack.unpack(dest, stage_dir)    

#         end == "f64997788eca9a5d020c4fe73921d4085fc07ea2266b1401276162efd4695678"
#     end

# end
