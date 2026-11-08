module MsixPack

#include("MSIX/MSIXPack.jl")
include("MSIX/WinSubsystem.jl")
include("MSIX/MSIX2EXEPack.jl")


using Makemsix_jll
using osslsigncode_jll
using OpenSSL_CLI_jll: openssl
using IconTools


include("utils.jl")

using Random: RandomDevice
using Base64

abstract type Signer end

struct PfxSigner <: Signer 
    path::String
    publisher::String
    password::String 
end

normalize_publisher(p) = join(strip.(split(p, ",")), ", ")

function subject(signer::Signer)
    return normalize_publisher(signer.publisher)
end

function generate_self_signed_certificate(pfx_path; password = "", publisher = "CN=AppBundler, C=XX, O=PeaceFounder", validity_days = 365)
    
    publisher_lined = join(reverse(split(publisher, ",")), '\n')

    code_sign_conf = """
    [ req ]
    default_bits = 2048
    prompt = no
    default_md = sha256
    distinguished_name = dn
    req_extensions = req_ext

    [ dn ]
    $publisher_lined

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


function generate_signer(; path = tempname(), publisher="O=AppBundler, C=XX, CN=AppBundler", validity_days = 365, force = true)

    if isfile(path)
        error("Certificate at $path alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(path))

    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))
    generate_self_signed_certificate(path; password, publisher, validity_days)

    return PfxSigner(path, publisher, password)
end


function extract_subject_from_certificate(cert_path; password = "")

    # Run the OpenSSL command and capture the output
    cmd = `$(openssl()) x509 -in $cert_path -noout -subject -nameopt RFC2253 -passin pass:$password`
    output = read(cmd, String)
    
    # Extract just the subject part
    if occursin("subject=", output)
        subject = replace(replace(output, r"subject= *" => "") |> strip, "\\,"=>",")
    else
        subject = replace(output |> strip, "\\,"=>",")
    end

    return replace(replace(subject, " "=>""), ","=>", ")
end


function isconsistent(signer::PfxSigner)
    publisher = extract_subject_from_certificate(signer.path; signer.password)
    return signer.publisher == publisher
end


function sign(destination, signer::PfxSigner; unsigned_msix = tempname())

    mv(destination, unsigned_msix)
    run(`$(osslsigncode()) sign -nolegacy -pkcs12 $(signer.path) -pass "$(signer.password)" -in "$unsigned_msix" -out "$destination"`)

    return
end


"""
    IconSource(path; plate = "#00000000")

Source image (`.svg`, `.png`) from which the MSIX `Assets/` directory is generated.
`plate` is the store tile background. Requires `using IconTools`.
"""
struct IconSource
    path::String
    store_icon_plate::String
end
IconSource(path; plate = "#00000000") = IconSource(path, plate)


function materialize(path::String, destination)
    mkpath(dirname(destination))
    cp(path, destination)
    return
end

function materialize(source::IconSource, destination)

    img = IconTools.load(source.path)
    mkpath(destination)
    for (file, icon) in IconTools.tomsix(img; source.store_icon_plate)
        IconTools.save(joinpath(destination, file), icon)
    end
    
    return
end

Base.@kwdef struct MSIXLayout
    manifest::String                                # AppxManifest.xml contents
    assets::Union{String,IconSource} = IconSource(joinpath(pkgdir(IconTools), "assets/icon.png"), "#f3f3f3")                # prepared Assets/ dir, or source to generate from
    resources_pri::Union{String,Nothing} = joinpath(dirname(@__DIR__), "assets/resources.pri")  # path, copied verbatim
    installer_data::Union{String,Nothing} = nothing # MSIXAppInstallerData.xml contents
end

# One could also load the MSIXLayout from existing packaging

function stage(msix::MSIXLayout, destination)

    if !isdir(destination)
        mkdir(destination)
    end

    materialize(msix.assets, joinpath(destination, "Assets"))

    write(joinpath(destination, "AppxManifest.xml"), msix.manifest)

    if !isnothing(msix.resources_pri)
        cp(msix.resources_pri, joinpath(destination, "resources.pri"))
    end

    if !isnothing(msix.installer_data)
        path = joinpath(destination, "Msix.AppInstaller.Data/MSIXAppInstallerData.xml")
        mkdir(dirname(path))
        write(path, msix.installer_data)
    end

    return
end

function update_publisher_in_manifest(appxmanifest_path, publisher)

    # Read the manifest file
    content = read(appxmanifest_path, String)
    
    # Replace the Publisher attribute value using regex
    updated_content = replace(content, r"Publisher=\"[^\"]*\"" => "Publisher=\"$publisher\"")
    
    # Write the updated content back to the file
    write(appxmanifest_path, updated_content)
end

# Let's keep ensure_windows_compatability(app_stage; path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths)
# function check_paths(dir; max_length = 260, skip_long_paths = :error,   # :error | :skip
#             symlinks = :error, non_ascii = :error)
# end

#function pack(app_stage, destination; signer::Union{Signer,Nothing} = nothing, verbose = false)

function pack(app_stage, destination; publisher = nothing, verbose = false)

    if !isnothing(publisher)
        appxmanifest = joinpath(app_stage, "AppxManifest.xml")
        update_publisher_in_manifest(appxmanifest, publisher)
    end
    
    #MSIXPack.pack(app_stage, destination)

    run(`$(makemsix()) pack -d $app_stage -p $destination`)
    #sign(destination, signer) # It could be moved to temporary directory and then signing could be made

    return
end

#escape_args(cmd::Cmd)::String                  # Windows argv quoting + XML attribute escaping

function unpack(source::String, destination::String)

    rm(destination; force=true, recursive=true)
    run(`$(makemsix()) unpack -ac -p $source -d $destination`)

    return
end



# """
#     MSIX2EXE([project]; prefix, preferences, bootstrap, windowed, sfx_stub, title)

# Create an MSIX-to-EXE configuration object for creating self-extracting Windows installers from MSIX packages.

# The resulting installer is a 7-Zip-based self-extracting executable. When launched, the executable extracts the MSIX package and the configured PowerShell bootstrap script to a temporary directory and then executes the bootstrap script with the extracted MSIX package as its argument.

# This is useful for distributing self-signed MSIX packages, since the bootstrap script can extract the package's signing certificate and install it into the system's trusted root store before launching the MSIX installer.

# When `project` is provided, configuration files (such as `msix/bootstrap.ps1`) are searched in `project`, then `project/meta`, then the built-in recipes directory, and packaging defaults are read from `project/LocalPreferences.toml`. Without `project`, only the built-in recipes and the active project's `LocalPreferences.toml` are used.

# # Arguments
# - `project`: Path to a project directory containing optional `LocalPreferences.toml` and optional `meta/msix/` overrides

# # Keyword Arguments
# - `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
# - `preferences`: Dictionary of packaging preferences used for the defaults below; read from `project` when given, otherwise from the active project
# - `bootstrap = get_path(prefix, "msix/bootstrap.ps1")`: Path to the bootstrap script which is embedded in the self-extracting installer. The script is invoked with the extracted MSIX package as its first argument
# - `windowed`: If `true`, run the bootstrap process without displaying a console window and launch the graphical MSIX installer; defaults to `msix.bootstrapper_windowed` preference
# - `sfx_stub = get(preferences, "msix2exe_sfx_stub", MSIX2EXEPack.extract_stub())`: Path to the 7-Zip self-extracting executable stub used to construct the installer
# - `title = "Installer"`: Title displayed by the self-extracting installer

# # Bootstrap Script

# The bootstrap script is invoked after the embedded files have been extracted, with the MSIX package path supplied as its first argument. For example:

# ```powershell
# powershell.exe bootstrap.ps1 msix_archive.msix
# ```
# """
# Base.@kwdef struct MSIX2EXE
#     bootstrap::String = joinpath(dirname(@__DIR__), "assets/bootstrap.ps1")
#     windowed::Bool = false
#     sfx_stub::String = MSIX2EXEPack.extract_stub() # Can be configured via preferences
#     title::String = "Installer"
# end


"""
    repack(msix_archive, msix2exe, destination; force=false)

Repackage an existing MSIX archive as a self-extracting EXE installer.

The MSIX archive and the PowerShell bootstrap script configured by `msix2exe::MSIX2EXE` are embedded into a 7-Zip self-extracting executable. When the resulting executable is launched, it extracts its contents to a temporary directory and runs the bootstrap script with the extracted MSIX archive as its argument.

# Arguments
- `msix_archive::String`: Path to the existing MSIX package to embed in the installer
- `msix2exe::MSIX2EXE`: configuration object describing the bootstrap script,
  SFX stub, window mode, and installer title
- `destination::String`: Path of the output self-extracting EXE

# Keyword Arguments
- `force = false`: If `true`, remove an existing file at `destination` before creating the installer

# Examples
```julia
spec = MSIX2EXE(project)
repack("MyApplication.msix", spec, "MyApplication.exe"; force = true)
```
"""
function msix2exe(msix_archive::String, destination::String;     
                  bootstrap::String = joinpath(dirname(@__DIR__), "assets/bootstrap.ps1"), 
                  windowed::Bool = false,
                  sfx_stub::String = MSIX2EXEPack.extract_stub(),
                  title::String = "Installer",
                  force = false)

    if force
        rm(destination; force=true)
    end
    
    MSIX2EXEPack.pack(msix_archive, bootstrap, destination; title, sfx_stub, console = !windowed)

    return
end




# function repack(source, destination; , password = "")

#     @info "Extracting MSIX"
#     extracted_msix = joinpath(tempdir(), "extracted_msix")
#     unpack(source, extracted_msix)

#     @info "Repackging MSIX"
#     pack(extracted_msix, destination; pfx_path, password)

#     return
# end



end # module MsixPack
