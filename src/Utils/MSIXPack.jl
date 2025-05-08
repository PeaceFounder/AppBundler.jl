module MSIXPack

using ZipFile
using Makemsix_jll
using osslsigncode_jll
using rcodesign_jll: rcodesign
using OpenSSL_jll: openssl

function extract_msix(archive_path::String)

    zip = ZipFile.Reader(archive_path)

    output_directory = joinpath(tempdir(), "zip_archive")
    rm(output_directory, recursive=true, force=true)

    for entry in zip.files
        if entry.method == ZipFile.Store
            outpath = joinpath(output_directory, entry.name)
            mkpath(outpath)
        end
    end


    for entry in zip.files
        if entry.method == ZipFile.Deflate
            outpath = joinpath(output_directory, entry.name)
            mkpath(dirname(outpath)) # Shouldn't be needed

            open(outpath, "w") do out_file
                write(out_file, read(entry))
            end
        end
    end

    close(zip)

    return output_directory
end


function extract_subject_from_certificate(cert_path; password = "")
    # Run the OpenSSL command and capture the output
    cmd = `$(openssl()) x509 -in $cert_path -noout -subject -nameopt RFC2253 -passin "pass:$password"`
    output = read(cmd, String)
    
    # Extract just the subject part
    if occursin("subject=", output)
        return replace(output, r"subject= *" => "")
    else
        return output
    end
end


function pack2msix(source, destination; pfx_path = nothing, password = "", replace_publisher = true)

    # I could create a self signed certificate from AppxManifest.xml
    # Need to make CN to match the AppxManifest.xml
    @assert !isnothing(pfx_path) "Not yet implemented"

    publisher = strip(extract_subject_from_certificate(pfx_path; password))
    @info "Using publisher: $publisher"

    appxmanifest = joinpath(source, "AppxManifest.xml")
    run(`sed -i '' "s/Publisher=\"[^\"]*\"/Publisher=\"$publisher\"/g" "$appxmanifest"`)


    @info "Forming MSIX archive"

    unsigned_msix = joinpath(tempdir(), "unsigned_msix.msix")
    rm(unsigned_msix; force=true)

    run(`$(makemsix()) pack -d $source -p $unsigned_msix`)

    @info "Performing codesigning"

    @info "signed msix at $destination"

    rm(destination; force=true)
    run(`$(osslsigncode()) sign -pkcs12 $pfx_path -pass "$password" -in "$unsigned_msix" -out "$destination"`)

    return
end


function generate_self_signed_certificate(pfx_path; password = "")
    code_sign_conf = """
    [ req ]
    default_bits = 2048
    prompt = no
    default_md = sha256
    distinguished_name = dn
    req_extensions = req_ext

    [ dn ]
    CN = AppBundler

    [ req_ext ]
    keyUsage = digitalSignature
    extendedKeyUsage = codeSigning
    """

    conf = joinpath(tempdir(), "code_sign.conf")
    rm(conf; force=true)
    write(conf, code_sign_conf)

    private_key = joinpath(tempdir(), "private.key")
    rm(private_key; force=true)
    
    certificate_crt = joinpath(tempdir(), "certificate.crt")
    rm(certificate_crt; force=true)

    # Generate private key and self-signed certificate
    run(`$(openssl()) req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$private_key" -out "$certificate_crt" -config "$conf"`)

    run(`$(openssl()) pkcs12 -export -out "$pfx_path" -inkey "$private_key" -in "$certificate_crt" -passout "pass:$password"`)

    
    return
end


# A helper function to explore potential issuess with msixpack
function repack(source, destination; pfx_path = nothing, publisher = nothing, password = "")

    extracted_msix = extract_msix(source)

    if isnothing(pfx_path)
        @warn "Creating one time self signed certificate"

        pfx_path = joinpath(tempdir(), "certificate.pfx")

        password = "YourPassword"
        publisher = "CN=AppBundler"
        generate_self_signed_certificate(pfx_path; password)
        
    end

    # CN=YourName, O=YourOrg, C=YourCountry

    # if !isnothing(publisher)

    #     appxmanifest = joinpath(extracted_msix, "AppxManifest.xml")
    #     run(`sed -i '' "s/Publisher=\"[^\"]*\"/Publisher=\"$publisher\"/g" "$appxmanifest"`)

    # end

    pack2msix(extracted_msix, destination; pfx_path, password)

    return
end


end
