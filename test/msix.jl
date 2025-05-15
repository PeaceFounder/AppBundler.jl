# Repack test
# import AppBundler.MSIXPack

#source = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/msix-hero-3.1.0.0.msix"
# destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/msix-hero-3.1.0.0-repack.msix"


# source = joinpath(homedir(), "Desktop/JuliaCon2024-AppBundler-Demo/PeaceFounderClient/build", "peacefounder-0.1.0-x64-win.msix")
# destination = joinpath(homedir(), "Desktop", "peacefounder-repacked.msix")

# MSIXPack.repack(source, destination)





import AppBundler: build_app, MSIXPack
import Pkg.BinaryPlatforms: Windows
using osslsigncode_jll
using OpenSSL_jll


src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")

destination = joinpath(tempdir(), "gtkapp.msix")
rm(destination; force=true)

@info "Building app at $destination"
build_app(Windows(:x86_64), src_dir, destination; precompile = Sys.iswindows())


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
    return true

end

verify_msix_signature(destination)


if Sys.iswindows()

    msixdir = MSIXPack.extract_msix(destination)

    

    # extract msix
    # check that properly precompiled
    #julia_exe = joinpath(temp_app_dir, "Contents/Libraries/julia/bin/julia")
    #run(`$julia_exe --compiled-modules=strict --pkgimages=existing --eval="using GTKApp"`)

end


