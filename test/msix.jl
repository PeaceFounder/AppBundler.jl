import AppBundler: build_app, build_msix, MSIXPack
import Pkg.BinaryPlatforms: Windows
using osslsigncode_jll
using OpenSSL_jll

#src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")

#destination = joinpath(tempdir(), "gtkapp.msix")
#destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/qmlapp.msix"
destination = joinpath(homedir(), "Documents/qmlapp.msix")
rm(destination; force=true)

# @info "Building app at $destination"
build_app(Windows(:x86_64), src_dir, destination; precompile = Sys.iswindows())

#build_app(Windows(:x86_64), src_dir, destination; precompile = Sys.iswindows())
#build_app(Windows(:x86_64), src_dir, destination; precompile = false)

# build_msix(src_dir, destination) do app_stage
#     @info "Performing a dry build at $app_stage"
# end

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


