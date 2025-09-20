module MSIXPack

using Makemsix_jll
using osslsigncode_jll
using rcodesign_jll: rcodesign
using OpenSSL_jll: openssl

function generate_self_signed_certificate(pfx_path; password = "", name = "AppBundler", country = "XX", organization = "PeaceFounder", validity_days = 365)
    code_sign_conf = """
    [ req ]
    default_bits = 2048
    prompt = no
    default_md = sha256
    distinguished_name = dn
    req_extensions = req_ext

    [ dn ]
    CN = $name
    C = $country
    O = $organization

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
    run(`$(openssl()) req -x509 -nodes -days $validity_days -newkey rsa:2048 -keyout "$private_key" -out "$certificate_crt" -config "$conf"`)

    run(`$(openssl()) pkcs12 -export -out "$pfx_path" -inkey "$private_key" -in "$certificate_crt" -passout "pass:$password"`)

    return
end

function extract_subject_from_certificate(cert_path; password = "")
    # Run the OpenSSL command and capture the output
    cmd = `$(openssl()) x509 -in $cert_path -noout -subject -nameopt RFC2253 -passin "pass:$password"`
    output = read(cmd, String)
    
    # Extract just the subject part
    if occursin("subject=", output)
        return replace(output, r"subject= *" => "") |> strip
    else
        return output |> strip
    end
end

function extract_publisher_from_manifest(appxmanifest_path)
    # Read the manifest file
    content = read(appxmanifest_path, String)
    
    # Extract the Publisher attribute using regex
    publisher_match = match(r"Publisher=\"([^\"]*)\"", content)
    
    if publisher_match !== nothing
        return publisher_match.captures[1]
    else
        return nothing  # Publisher attribute not found
    end
end

function update_publisher_in_manifest(appxmanifest_path, publisher)

    publisher = replace(publisher, ","=>", ")

    # Read the manifest file
    content = read(appxmanifest_path, String)
    
    # Replace the Publisher attribute value using regex
    updated_content = replace(content, r"Publisher=\"[^\"]*\"" => "Publisher=\"$publisher\"")
    
    # Write the updated content back to the file
    write(appxmanifest_path, updated_content)
end

function pack(source, destination; pfx_path = nothing, password = "")

    if isnothing(pfx_path)
        @warn "Creating one time self signed certificate"
        pfx_path = joinpath(tempdir(), "certificate.pfx")
        generate_self_signed_certificate(pfx_path; password)
    end

    publisher = extract_subject_from_certificate(pfx_path; password)
    @info "Using publisher: $publisher"

    appxmanifest = joinpath(source, "AppxManifest.xml")

    publisher_manifest = extract_publisher_from_manifest(appxmanifest)
    
    if publisher_manifest == ""
        @info "Setting publisher to $publisher"
    elseif publisher_manifest != publisher
        @warn "Publisher in manifest is $publisher_manifest wheras in certificate $publisher. Using the latter"
    end

    update_publisher_in_manifest(appxmanifest, publisher)

    @info "Forming MSIX archive"
    unsigned_msix = joinpath(tempdir(), "unsigned_msix.msix")
    rm(unsigned_msix; force=true)

    run(`$(makemsix()) pack -d $source -p $unsigned_msix`)

    @info "Performing codesigning with certificate at $pfx_path"

    rm(destination; force=true)
    run(`$(osslsigncode()) sign -pkcs12 $pfx_path -pass "$password" -in "$unsigned_msix" -out "$destination"`)

    @info "Signed MSIX at $destination"

    return
end

function unpack(source::String, destination::String)

    rm(destination; force=true, recursive=true)
    run(`$(makemsix()) unpack -ac -p $source -d $destination`)

    return
end

# A helper function to explore potential issuess with msixpack
function repack(source, destination; pfx_path = nothing, publisher = nothing, password = "")

    @info "Extracting MSIX"
    extracted_msix = joinpath(tempdir(), "extracted_msix")
    unpack(source, extracted_msix)
    #@show extracted_msix = extract_msix(source)

    @info "Repackging MSIX"
    pack(extracted_msix, destination; pfx_path, password)

    return
end

end
