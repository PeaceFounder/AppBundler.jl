module DMGPack

using rcodesign_jll: rcodesign
using ..DSStore
using ..HFSTools
using ..HFSImg: build_hfs
using libdmg_hfsplus_jll: dmg, hfsplus
using Xorriso_jll: xorriso
using Dates: DateTime


"""
    ImageBackend

Abstract supertype for disk image backends used by [`DMG`](@ref). A backend implements two methods:

- `build_image(backend, stage, img; volume_name, verbose)`: create a raw disk image `img` from the staging directory `stage`
- `compress_image(backend, img, destination; compression)`: convert the raw image into a compressed `.dmg` at `destination`

See [`XorrisoBackend`](@ref) and [`HFSPlusBackend`](@ref).
"""
abstract type ImageBackend end

"""
    XorrisoBackend(; hfsplus = false)

Image backend that builds the disk image with `xorriso` (`-as mkisofs`) and compresses it with `dmg dmg` from libdmg-hfsplus.

The image is an ISO 9660 filesystem with Rock Ridge extensions (preserving POSIX permissions and symlinks) and relaxed filenames.

# Keyword Arguments
- `hfsplus = false`: If `true`, pass `-hfsplus` to `xorriso` so the image also carries an HFS+ filesystem, which macOS mounts natively. If `false`, the image is a plain ISO 9660 image.

Selected with the `dmg.backend = "xorriso"` preference; `hfsplus` is read from `dmg.xorriso.hfsplus`.
"""
@kwdef struct XorrisoBackend <: ImageBackend
    hfsplus::Bool = false
end

"""
    build_image(backend::XorrisoBackend, stage, img; volume_name = "", verbose = true)

Create the ISO image `img` from the directory `stage` using `xorriso`, with `volume_name` as the volume label.
"""
function build_image(backend::XorrisoBackend, stage, img; volume_name = "", verbose = true)

    hfsplus_flag = backend.hfsplus ? `-hfsplus` : ``
    run(`$(xorriso()) -as mkisofs -V "$volume_name" $hfsplus_flag -relaxed-filenames -D -R -no-pad -o $img $stage`)

    return
end

"""
    compress_image(backend::XorrisoBackend, img, destination; compression = :lzma)

Convert the ISO image `img` into a compressed `.dmg` at `destination` with `dmg dmg`. `compression` is one of `:lzma`, `:bzip2`, `:zlib` or `:lzfse`.
"""
function compress_image(backend::XorrisoBackend, img, destination; compression = :lzma)
    run(`$(dmg()) dmg $img $destination --compression=$compression`)
    return
end

"""
    HFSPlusBackend(; free_space = 0, blocksize = 4096, uid = 99, gid = 99, timestamp = nothing, uuid = rand(UInt64))

Image backend that builds an HFS+ volume with the pure-Julia `HFSImg.build_hfs` and compresses it with `dmg build` from libdmg-hfsplus.

The volume is sized to fit the staged contents exactly, plus `free_space`. Permission bits, modification times and symlinks are preserved; hard links become separate copies. Names that collide on case-insensitive HFS+ (including Unicode-normalization collisions) are rejected.

# Keyword Arguments
- `free_space = 0`: Extra free space in bytes to add to the volume, rounded up to whole blocks
- `blocksize = 4096`: Allocation block size in bytes; must be a power of two ≥ 512
- `uid = 99`, `gid = 99`: Owner and group recorded for every item (99 is "unknown", which macOS maps to the current user)
- `timestamp = nothing`: If set (a UTC `DateTime`), forces the dates of all items and of the volume. With `nothing`, each item keeps its own mtime and the volume takes the newest one
- `uuid = rand(UInt64)`: Non-zero 64-bit volume identifier. It is the only random part of an image

For byte-for-byte reproducible images, fix both `timestamp` and `uuid` (the default `uuid` is drawn randomly each time the backend is constructed).

Selected with the `dmg.backend = "hfsplus"` preference; `free_space` is read from `dmg.hfsplus.free_space`.
"""
@kwdef struct HFSPlusBackend <: ImageBackend
    free_space::Integer = 0
    blocksize::Integer = 4096
    uid::Integer = 99
    gid::Integer = 99
    timestamp::Union{Nothing, DateTime} = nothing
    uuid::UInt64 = rand(UInt64)
end

"""
    build_image(backend::HFSPlusBackend, stage, img; volume_name = "untitled", verbose = false)

Create the HFS+ image `img` from the directory `stage` with `HFSImg.build_hfs`, using `volume_name` as the volume name. `verbose` is accepted for interface compatibility and is unused.
"""
function build_image(backend::HFSPlusBackend, stage, img; volume_name = "untitled", verbose = false)

    (; free_space, blocksize, uid, gid, timestamp, uuid) = backend
    build_hfs(stage, img; volname = volume_name, free_space, blocksize, uid, gid, timestamp, uuid)

    return
end

"""
    compress_image(backend::HFSPlusBackend, img, destination; compression = :lzma)

Convert the HFS+ image `img` into a compressed `.dmg` at `destination` with `dmg build`. `compression` is one of `:lzma`, `:bzip2`, `:zlib` or `:lzfse`.
"""
function compress_image(backend::HFSPlusBackend, img, destination; compression = :lzma)
    
    run(`$(dmg()) build $img $destination --compression=$compression`)
    
    return
end


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
function pack(app_stage, destination, entitlements; pfx_path = nothing, password = "", compression = :lzma, installer_title = "Installer", hardened_runtime = true, shallow_signing = true, backend = XorrisoBackend(false), verbose = true)

    isfile(entitlements) || error("Entitlements at $entitlements not found")
    isnothing(compression) || compression in [:lzma, :bzip2, :zlib, :lzfse] || error("Compression can only be `compression=[:lzma|:bzip|:zlib|:lzfse]`")
    isnothing(pfx_path) || isfile(pfx_path) || error("Signing certificate at $pfx_path not found")

    if !isnothing(pfx_path)
        println("Codesigning application bundle at $app_stage with certificate at $pfx_path")        

        shallow_flag = shallow_signing ? `--shallow` : ``
        runtime_flag = hardened_runtime ? `--code-signature-flags runtime` : ``

        run(`$(rcodesign()) sign $shallow_flag --p12-file "$pfx_path" --p12-password "$password" $runtime_flag --entitlements-xml-path "$entitlements" "$app_stage"`)
    else
        @warn "Skipping codesigning. Use `--selfsign` to codesign your code with self signed certificate."
    end

    if !isnothing(compression)

        img = tempname() 

        println("Forming image at $img")
        build_image(backend, dirname(app_stage), img; volume_name = installer_title, verbose)

        println("Compressing img to dmg with $compression algorithm at $destination")
        compress_image(backend, img, destination; compression)

        if !isnothing(pfx_path) && !shallow_signing
            println("Codesigning DMG bundle with certificate at $pfx_path")
            run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
        end
    end

    return
end

function unpack(source, destination; verbose = false)

    raw_image = tempname()
    run(`$(dmg()) extract $source $raw_image`)
    HFSTools.extract_hfs_filesystem(raw_image, destination)

    if verbose
        HFSTools.explore_hfs_image(raw_image)
    end

    return
end

end
