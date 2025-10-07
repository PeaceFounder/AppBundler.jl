using Test

import AppBundler: stage, bundle, MSIX, DMG, Snap
import AppBundler

using osslsigncode_jll
using OpenSSL_jll

using SHA

function hash_stage(f)
    stage = mktempdir()
    f(stage)
    return hash_directory(stage)
end

# Read file and compute SHA-256 hash
function hash_file(filename)
    hash_bytes = sha256(read(filename))
    hash_string = bytes2hex(hash_bytes)
    return hash_string
end    

# TODO: Need to investigate this function for windows
# likelly sorting with `\` is the issue there
# It would also be useful to add relative filename in the hash for fixing that
function hash_directory(dir_path)
    if !isdir(dir_path)
        error("Directory not found: $dir_path")
    end
    
    # Get all files recursively and sort for consistency
    all_files = String[]
    for (root, dirs, files) in walkdir(dir_path)
        for file in files
            push!(all_files, joinpath(root, file))
        end
    end
    sort!(all_files)  # Ensure consistent ordering

    # Create hash context properly
    ctx = SHA.SHA256_CTX()  # Create context this way
    
    # Hash each file's content
    for filepath in all_files
        file_data = read(filepath)
        println("$(hash(file_data)): $filepath")
        SHA.update!(ctx, file_data)
    end
    
    return bytes2hex(SHA.digest!(ctx))
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

@time @testset "MSIX bundling tests" begin

    msix = MSIX(joinpath(@__DIR__, "../examples/gtkapp"))

    @test hash_stage() do dest
        stage(msix, dest)
        AppBundler.MSIXPack.update_publisher_in_manifest(joinpath(dest, "AppxManifest.xml"), "AppBundler")
    end == "07bf7bdbf24a7ea2cb0025db9995680b596436698bba4663ffeb67eba82f44c7" 

    @test hash_stage() do stage_dir

        dest = joinpath(mktempdir(), "gtkapp.msix")
        bundle(msix, dest) do app_stage
            @info "The MSIX app stage is $app_stage"
        end

        verify_msix_signature(dest)

        AppBundler.MSIXPack.unpack(dest, stage_dir)
        rm(joinpath(stage_dir, "AppxSignature.p7x")) # Signatures are always nondeterministic

        AppBundler.MSIXPack.update_publisher_in_manifest(joinpath(stage_dir, "AppxManifest.xml"), "AppBundler")
        
        # @test hash_file(joinpath(stage_dir, "AppxBlockMap.xml")) == "70ff6695ec913326f645c1cd30e48f75f57545ee4ae546db5843bf0779e6ee7e"
        rm(joinpath(stage_dir, "AppxBlockMap.xml")) # AppxBlockMap.xml has a slight nondeterminism

    end == "07bf7bdbf24a7ea2cb0025db9995680b596436698bba4663ffeb67eba82f44c7"

end

if Sys.isunix()

    # ------------------- DMG -------------

    @time @testset "DMG bundling tests" begin

        dmg = DMG(joinpath(@__DIR__, "../examples/gtkapp"))

        @test hash_stage() do dest
            stage(dmg, joinpath(dest, "gtkapp.app"); dsstore=true, main_redirect=true)
            AppBundler.DMGPack.replace_binary_with_hash(joinpath(dest, "gtkapp.app/Contents/MacOS/gtkapp"))
            rm("$dest/Applications")
        end == "9f42d0a55ae871c707b5106b6aa1875a9138fdf9815cc3c3b2a794ccf6a4c9f6"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.dmg")
            bundle(dmg, dest; main_redirect=true) do app_stage
                @info "The DMG app stage is $app_stage"
            end

            AppBundler.DMGPack.unpack(dest, stage_dir)

            if Sys.isapple()
                # This check is also important for stagging
                @info "Verifying that the application is correctly codesigned"
                run(`codesign -v --verbose=4 $stage_dir/gtkapp.app`)
            end

            @show AppBundler.DMGPack.replace_binary_with_hash(joinpath(stage_dir, "gtkapp.app/Contents/MacOS/gtkapp"))
            rm("$stage_dir/gtkapp.app/Contents/_CodeSignature"; recursive=true)

        end == "9f42d0a55ae871c707b5106b6aa1875a9138fdf9815cc3c3b2a794ccf6a4c9f6"

    end

    # -------------------- SNAP -----------------

    @time @testset "Snap bundling tests" begin

        snap = Snap(joinpath(@__DIR__, "../examples/gtkapp"))

        @test hash_stage() do dest
            stage(snap, dest; install_configure=true)
        end == "947184f6a758540e3b2a60701c8c92790264edd6db3319bbadaa5fb55a0e8dc6"

        @test hash_stage() do stage_dir

            dest = joinpath(mktempdir(), "gtkapp.snap")
            bundle(snap, dest; install_configure=true) do app_stage
                @info "The DMG app stage is $app_stage"
            end
            
            AppBundler.SnapPack.unpack(dest, stage_dir)    
        end == "947184f6a758540e3b2a60701c8c92790264edd6db3319bbadaa5fb55a0e8dc6"

    end

end
