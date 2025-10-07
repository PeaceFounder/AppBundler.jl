module DMGPack

using libdmg_hfsplus_jll: dmg
using Xorriso_jll: xorriso
using rcodesign_jll: rcodesign
using ..DSStore
using ..HFS

function generate_self_signing_pfx(pfx_path; password = "PASSWORD")

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="AppBundler" --p12-file="$pfx_path" --p12-password="$password"`)

end


"""
    pack(app_stage, destination, entitlements; pfx_path = nothing, password = "", compression = :lzma, installer_title = "Installer")

Create a macOS disk image (DMG) from an application bundle with code signing and customizable appearance.

This function handles the complete process of packaging a macOS application for distribution. It code signs the application bundle with appropriate entitlements, creates a professional-looking installer disk image with optional custom appearance, sets up the drag-and-drop installation experience by including a symbolic link to Applications, applies the selected compression algorithm to minimize file size, and code signs the final DMG for security and integrity. The resulting DMG file follows Apple's distribution guidelines and provides end users with the familiar installation experience of dragging the application to their Applications folder.

The function assumes that `app_stage` points to a properly structured macOS application bundle (`.app` directory). Importantly, the parent directory of `app_stage` serves as the staging area from which the DMG file is created. This means that any files present in this parent directory will be included in the final DMG. The function automatically creates a symbolic link to `/Applications` in this parent directory to facilitate drag-and-drop installation, and it may modify or create a `.DS_Store` file in this directory to control the appearance of the DMG when opened.

# Arguments
- `app_stage::String`: Path to the application bundle (`.app` directory) to be packaged
- `destination::String`: Path where the resulting DMG file should be saved
- `entitlements::String`: Path to an XML file containing the entitlements for code signing

# Keyword Arguments
- `pfx_path::Union{String, Nothing} = nothing`: Path to a PKCS#12 certificate file for code signing. If not provided, a temporary self-signed certificate will be generated
- `password::String = ""`: Password for the certificate file
- `compression::Union{Symbol, Nothing} = :lzma`: Compression algorithm to use for the DMG. Options are `:lzma`, `:bzip2`, `:zlib`, `:lzfse`, or `nothing` for no compression
- `installer_title::String = "Installer"`: Volume name for the DMG
"""
function pack(app_stage, destination, entitlements; pfx_path = nothing, password = "", compression = :lzma, installer_title = "Installer")

    isfile(entitlements) || error("Entitlements at $entitlements not found")
    isnothing(compression) || compression in [:lzma, :bzip2, :zlib, :lzfse] || error("Compression can only be `compression=[:lzma|:bzip|:zlib|:lzfse]`")
    isnothing(pfx_path) || isfile(pfx_path) || error("Signing certificate at $pfx_path not found")

    if isnothing(pfx_path) 
        @warn "Creating a one time self signing certificate..."
        pfx_path = joinpath(tempdir(), "certificate_macos.pfx")
        generate_self_signing_pfx(pfx_path; password = "")
    end

    @info "Codesigning application bundle at $app_stage with certificate at $pfx_path"

    
    run(`$(rcodesign()) sign --shallow --p12-file "$pfx_path" --p12-password "$password" --entitlements-xml-path "$entitlements" "$app_stage"`)
    
    if !isnothing(compression)

        @info "Setting up packing stage at $(dirname(app_stage))"

        iso_stage = tempname()

        @info "Forming iso archive with xorriso at $iso_stage"
        run(`$(xorriso()) -as mkisofs -V "$installer_title" -hfsplus -hfsplus-file-creator-type APPL APPL $(basename(app_stage)) -hfs-bless-by x / -relaxed-filenames -no-pad -o $iso_stage $(dirname(app_stage))`)
        @info "Compressing iso to dmg with $compression algorithm at $destination"
        run(`$(dmg()) dmg $iso_stage $destination --compression=$compression`)

        @info "Codesigning DMG bundle with certificate at $pfx_path"
        run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
    end

    return
end

function unpack(source, destination)

    raw_image = tempname()
    run(`$(dmg()) extract $source $raw_image`)
    HFS.extract_hfs_filesystem(raw_image, destination)

    HFS.explore_hfs_image(raw_image)

    return
end

"""
    replace_file_with_hash(filepath::String)

Computes the code hash of a file using rcodesign and replaces the file 
with the rcodesign output directly.
"""
function replace_binary_with_hash(filepath::String)
    if !isfile(filepath)
        error("File does not exist: $filepath")
    end
    
    try
        # Get rcodesign output and write directly to file
        hash_output = read(`$(rcodesign()) compute-code-hashes $filepath`, String)
        lines = split(strip(hash_output), '\n')
        stripped_output = join(lines[2:end], '\n') * '\n'
        write(filepath, stripped_output)
        println("Replaced $filepath with its hash(es)")
        return hash_output
    catch e
        error("Failed to process $filepath: $e")
    end
end

end
