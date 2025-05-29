import AppBundler: build_app, build_msix, MSIXPack
import Pkg.BinaryPlatforms: Windows
using osslsigncode_jll
using OpenSSL_jll

src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")

destination = joinpath(tempdir(), "qmlapp.msix")
rm(destination; force=true)

build_msix(src_dir, destination) do app_stage
    @info "Performing a dry build at $app_stage"
end

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

verify_msix_signature(destination)

# We are only checking that full bundling works on the coresponding platform to save CI time
if Sys.iswindows()
    @info "Performing full MSIX bundling test"

    destination = joinpath(tempdir(), "qmlapp.msix")
    rm(destination; force=true, recursive=true)

    build_app(Windows(:x86_64), src_dir, destination; precompile = true, debug=true)

    @info "Extracting MSIX and verifing validity"

    msixdir = joinpath(tempdir(), "msixdir")
    MSIXPack.unpack(destination, msixdir)

    julia_exe = joinpath(msixdir, "julia/bin/julia.exe")
    run(`$julia_exe --compiled-modules=strict --pkgimages=existing --eval="using QMLApp"`)
else
    @info "Performing MSIX directory bundling test"

    destination = joinpath(tempdir(), "qmlapp")
    rm(destination; force=true, recursive=true)

    build_app(Windows(:x86_64), src_dir, destination; precompile = false, debug=true)
end


