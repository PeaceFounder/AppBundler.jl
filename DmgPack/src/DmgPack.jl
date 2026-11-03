module DmgPack

include("DMG/DSStore.jl")
include("DMG/HFSTools.jl")
include("DMG/HFSImg.jl")
#include("DMG/DMGPack.jl")

using rcodesign_jll: rcodesign
using Random: RandomDevice
using Base64
using Dates
using Base.BinaryPlatforms: Platform # Need to revise this part to rmove Pkg dependency
import AppBundlerUtils_jll
using Artifacts


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


abstract type Signer end

struct PfxSigner <: Signer
    path::String
    password::String
end


function generate_self_signed_certificate(destination; person_name = "AppBundler", country = "XX", validity_days = 365, force=false, password = "")
    
    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="$person_name" --p12-file="$destination" --p12-password="$password" --country-name=$country --validity-days="$validity_days"`)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/macos/certificate.pfx; To use certificate set certificate password "$password"
    """)

    return password
end

function generate_signer(; path = tempname(), person_name = "AppBundler", country = "XX", validity_days = 365, force = true)

    if isfile(path)
        error("Certificate at $path alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(path))

    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))
    generate_self_signed_certificate(path; person_name, country, validity_days)

    return PfxSigner(path, password)
end


function materialize_dsstore(dsstore::Dict, destination::String)

    mkpath(dirname(destination))

    DSStore.open_dsstore(destination, "w+") do ds

        ds[".", "icvl"] = ("type", "icnv")
        ds[".", "vSrn"] = ("long", 1)

        for file_key in keys(dsstore)
            file_dict = dsstore[file_key]
            for entry_key in keys(file_dict)
                ds[file_key, entry_key] = file_dict[entry_key]
            end
        end
    end

    return
end

function materialize_dsstore(dsstore::String, destination::String)
    mkpath(dirname(destination))
    cp(dsstore, destination)
end





"""
    IconSource(path)

Source image (`.svg`, `.png`) from which `icon.icns` is generated. Requires `using IconTools`.
"""
struct IconSource
    path::String
end

function materialize_icon(source, destination)
    mkpath(dirname(destination))
    cp(source, destination)
end

function materializ_icon(source, destination)

    mkpath(dirname(destination))
    img = IconTools.load(src)
    write(dest, IconTools.toicns(img))

    return
end

Base.@kwdef struct DMGLayout
    bundle_name::String                             # → <root>/<bundle_name>; expected with .app extension
    info_plist::String                              # Info.plist contents
    icon::Union{String, IconSource} = IconSource(joinpath(pkgdir(IconTools), "assets/icon.svg"))
    launcher::Union{String,Nothing} = nothing       # path → Contents/MacOS/<executable>, executable bit set
    dsstore::Union{Dict, String, Nothing} = nothing  # Finder entries → <root>/.DS_Store
    applications_link::Bool = true                  # → <root>/Applications -> /Applications
end


function stage(dmg::DMGLayout, destination::String)


    #bundle_dir = joinpath(destination, "$(dmg.bundle_name).app", "Contents")
    bundle_dir = joinpath(destination, bundle_name, "Contents")

    materialize_icon(dmg.icon, joinpath(bundle_dir, "Resources/icon.icns"))

    write(joinpath(bundle_dir, "Info.plist"), dmg.info_plist)
    
    if !isnothing(dmg.launcher)

        #    executable_name::Union{String,Nothing} = nothing     # default: CFBundleExecutable of info_plist
        executable_name = "myapp" # ToDo: some regex magic
        exe_path = joinpath(bundle_dir, "MacOS", executable_name)

        mkpath(dirname(exe_path))
        cp(dmg.launcher, exe_path)
        chmod(exe_path, 0o755)

    end

    if !isnothing(dmg.dsstore)
        materialize_dsstore(dmg.dsstore, joinpath(destination, ".DS_Store"))
    end

    symlink("/Applications", joinpath(destination, "Applications"); dir_target=true)

    return
end

function sign(app_stage, signer::PfxSigner; entitlements = nothing, shallow_signing = true, hardened_runtime = true)

    shallow_flag = shallow_signing ? `--shallow` : ``
    runtime_flag = hardened_runtime ? `--code-signature-flags runtime` : ``

    if isnothing(entitlements)
        enitlements_flag = ``
    else
        entitlements_path = tempname()
        write(entitlements_path, entitlements)
        enitlements_flag = `--entitlements-xml-path $entitlements_path`
    end

    run(`$(rcodesign()) sign $shallow_flag --p12-file "$(signer.path)" --p12-password "$password" $runtime_flag $entitlements_flag "$app_stage"`)

    return
end


function clean_app_stage(app_stage)

    # Remove AppleDouble metadata files (._*) that macOS creates to preserve extended attributes
    # and executable permissions on non-HFS+ filesystems. These files are created by xorriso during
    # ISO creation but get stripped during DMG compression, causing codesign verification to fail
    # when the installed app is checked, since the code signature references files that no longer exist.
    # Example errors without this cleanup:
    #   file missing: .../SparseArrays/gen/._generator.jl
    #   file missing: .../julia/._julia-config.jl
    #   file missing: .../terminfos/._make-fancy-terminfo.sh
    # These ._* files typically appear alongside executable .jl or .sh files in the Julia stdlib.
    run(`find $app_stage -name "._*" -delete`)

    return
end




function pack(root, destination;
              #volume_name,                                    # ≤ 32 characters, checked here
              installer_title,
              #signer::Union{Signer,Nothing} = nothing,
              #entitlements_path = nothing,
              #entitlements = nothing,
              compression = :lzma,                            # :lzma | :bzip2 | :zlib | :lzfse | nothing
              #shallow_signing = false, 
              #hardened_runtime = true,
              backend = XorrisoBackend(), 
              verbose = false)


    if length(installer_title) > 32
        error("Installer title \"$installer_title\" exceeds the maximum 32 characters allowed by xorriso (current length: $(length(installer_title))). Please shorten APP_DISPLAY_NAME to $(32 - length(" Installer")) characters or less.")
    end

    compression in [:lzma, :bzip2, :zlib, :lzfse] || error("Compression can only be `compression=[:lzma|:bzip|:zlib|:lzfse]`")

    
    

    img = tempname() 

    println("Forming image at $img")
    build_image(backend, root, img; volume_name, verbose)

    println("Compressing img to dmg with $compression algorithm at $destination")
    compress_image(backend, img, destination; compression)

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

function notarize(destination, signer::PfxSigner, notary)

    run(`$(rcodesign()) sign --p12-file "$(signer.path)" --p12-password "$(signer.password)" "$destination"`)

    return
end

function launcher_stub(arch::String)

    platform = Platform(arch, "macos")

    artifacts_toml = joinpath(dirname(dirname(pathof(AppBundlerUtils_jll))), "Artifacts.toml")
    meta = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]
    hash = Base.SHA1(meta["git-tree-sha1"])

    Artifacts.artifact_exists(hash) || error(
        "AppBundlerUtils artifact for $(Base.BinaryPlatforms.triplet(platform)) is not installed. " *
        "Run `import Pkg; Pkg.build(\"AppBundler\")` to install it.")

    return joinpath(Artifacts.artifact_path(hash), "bin", "macos_launcher")
end


launcher_stub(arch::Symbol) = launcher_stub(string(arch))


"""
    xml_escape_args(args) -> String

Turn an argument list (or a `Cmd`, whose first element is dropped as the executable)
into a string suitable for an AppxManifest `Parameters="..."` attribute: arguments are
quoted following Windows argv rules and then escaped for an XML attribute.
"""
function xml_escape_args(args::AbstractVector{<:AbstractString})
    isempty(args) && return ""
    cmdline = Base.escape_microsoft_c_args(args...)   # Windows argv quoting
    return xml_escape_attr(cmdline)                   # XML attribute escaping
end

xml_escape_args(cmd::Cmd) = xml_escape_args(cmd[2:end])

function xml_escape_attr(s::AbstractString)
    io = IOBuffer()
    for c in s
        if     c == '&'  print(io, "&amp;")
        elseif c == '<'  print(io, "&lt;")
        elseif c == '>'  print(io, "&gt;")
        elseif c == '"'  print(io, "&quot;")
        elseif c == '\'' print(io, "&apos;")
        elseif c == '\t' print(io, "&#9;")    # otherwise normalized to a space
        elseif c == '\n' print(io, "&#10;")
        elseif c == '\r' print(io, "&#13;")
        elseif c < ' '
            throw(ArgumentError("control character $(repr(c)) cannot appear in XML 1.0"))
        else
            print(io, c)
        end
    end
    return String(take!(io))
end


function __init__()

    DSStore.__init__()

end


end # module DmgPack
