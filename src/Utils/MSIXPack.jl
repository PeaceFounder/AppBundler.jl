module MSIXPack

using ZipFile
using Makemsix_jll
using osslsigncode_jll
using rcodesign_jll: rcodesign
using OpenSSL_jll: openssl

# A short term workaround until cross compilation of makemsix will be sorted out
# with binary builder. 
if Sys.iswindows()
    @eval makemsix() = joinpath(@__DIR__, "../../bin/makemsix.exe")
end

function is_windows_compatible(filename::String; path_length_threshold)
    # Check for invalid characters

    if occursin(r"[<>:\"\\\|?*\x00-\x1F]", filename) || occursin(r"[\x7F-\x9F]", filename)
        @warn "$(filename) contains invalid characters for Windows."
        return false
    end
    # if occursin(r"[\\/:*?\"<>|]", filename)
    #     @warn "$filename contains invalid characters for Windows.\n"
    #     return false
    # end

    # Check for reserved names
    reserved_names = ["CON", "PRN", "AUX", "NUL"]
    reserved_names_with_numbers = [string(name, i) for name in ["COM", "LPT"] for i in 1:9]
    append!(reserved_names, reserved_names_with_numbers)

    basename_no_ext = splitext(basename(filename))[1]
    if uppercase(basename_no_ext) in reserved_names
        @warn "$filename is a reserved name in Windows.\n"
        return false
    end

    # # Check filename length (Windows max path is 260 characters)
    if length(filename) > path_length_threshold
        @warn "$filename exceeds Windows max path length.\n"
        return false
    end

    return true
end

function ensure_windows_compatability(src_dir::String; path_length_threshold::Int = 260, skip_long_paths::Bool = false)

    error_paths = []
    
    max_length = 0

    for (root, dirs, files) in walkdir(src_dir)
        for file in files
            filepath = joinpath(root, file)
            rel_path = relpath(filepath, src_dir)
            
            if skip_long_paths && length(rel_path) > path_length_threshold
                rm(filepath)
                continue
            end

            if !is_windows_compatible(rel_path; path_length_threshold)
                push!(error_paths, rel_path)
                #error("Aborting due to Windows-incompatible filename.")
            end

            if length(rel_path) > max_length
                max_length = length(rel_path)
            end
        end
    end

    # removing empty direcotories
    for (root, dirs, files) in walkdir(src_dir, topdown=false)
        for dir in dirs
            path = joinpath(root, dir)
            if isempty(readdir(path))
                rm(path)
            end
        end
    end

    @info "Maximum relative path length is $max_length"

    if length(error_paths) > 0
        #@warn "$(length(error_paths)) errors detected"
        error("$(length(error_paths)) errors detected")
    end

    return
end

function generate_self_signed_certificate(pfx_path; password = "", name = "AppBundler", country = "XX", organization = "PeaceFounder")
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
    run(`$(openssl()) req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$private_key" -out "$certificate_crt" -config "$conf"`)

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

function pack2msix(source, destination; pfx_path = nothing, password = "", path_length_threshold::Int = 260, skip_long_paths::Bool = false)


    Sys.iswindows() || ensure_windows_compatability(source; path_length_threshold, skip_long_paths)

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

    @info "Performing codesigning"

    @info "signed MSIX at $destination"

    rm(destination; force=true)
    run(`$(osslsigncode()) sign -pkcs12 $pfx_path -pass "$password" -in "$unsigned_msix" -out "$destination"`)

    return
end

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

# A helper function to explore potential issuess with msixpack
function repack(source, destination; pfx_path = nothing, publisher = nothing, password = "")

    @info "Extracting MSIX"
    extracted_msix = extract_msix(source)

    pack2msix(extracted_msix, destination; pfx_path, password)

    return
end

end
