import Pkg, Artifacts
using Pkg.BinaryPlatforms: MacOS
using AppBundlerUtils_jll
using Preferences
import Mustache

"""
    MSIX(; prefix, icon, appxmanifest, resources_pri, msixinstallerdata, path_length_threshold, skip_long_paths, pfx_cert, parameters)

Create an MSIX configuration object for Windows application packaging.

This constructor initializes an MSIX configuration with paths to required Windows packaging files
and settings for path length handling and code signing.

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true)`: Path to application icon file or Assets directory
- `appxmanifest = get_path(prefix, "msix/AppxManifest.xml")`: Path to MSIX application manifest template
- `resources_pri = get_path(prefix, "msix/resources.pri")`: Path to package resource index file
- `msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml")`: Path to installer configuration template
- `path_length_threshold = 260`: Maximum allowed path length for files in the MSIX package
- `skip_long_paths = false`: If `true`, skip files exceeding path length threshold; if `false`, throw an error
- `skip_symlinks = true`: If `true`, skip file and directory symlinks
- `pfx_cert = get_path(prefix, "msix/certificate.pfx")`: Path to code signing certificate (optional)
- `parameters = Dict()`: Dictionary of parameters for template rendering (e.g., APP_NAME, APP_VERSION)

# Examples
```julia
# Create MSIX config with default recipes
msix = MSIX()

# Create MSIX config from project overlay
msix = MSIX(app_dir)

# Create MSIX config with custom settings
msix = MSIX(
    icon = "custom_icon.png",
    path_length_threshold = 200,
    skip_long_paths = true
)

# Create MSIX config with multiple search directories
msix = MSIX(
    prefix = ["custom/", "defaults/", "recipes/"]
)
```
"""
struct MSIX
    icon::String # direcotry reading is something to look into here
    appxmanifest::String 
    msixinstallerdata::String 
    resources_pri::String
    path_length_threshold::Int 
    skip_long_paths::Bool 
    skip_symlinks::Bool
    skip_unicode_paths::Bool
    selfsign::Bool
    publisher::String
    pfx_cert::Union{String, Nothing} 
    windowed::Bool
    compress::Bool
    arch::Symbol
    predicate::Symbol
    parameters::Dict{String, Any}
end

function MSIX(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true),
              appxmanifest = get_path(prefix, "msix/AppxManifest.xml"),
              resources_pri = get_path(prefix, "msix/resources.pri"),
              msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml"),
              path_length_threshold = @load_preference("msix_path_length_threshold"),
              skip_long_paths = @load_preference("msix_skip_long_paths"),
              skip_symlinks = @load_preference("msix_skip_symlinks"),
              skip_unicode_paths = @load_preference("msix_skip_unicode_paths"),
              selfsign = false,              
              publisher = @load_preference("msix_publisher") |> normalize_publisher,   #get_publisher(pfx_cert, selfsign),
              pfx_cert = get_path(prefix, "msix/certificate.pfx"), # We actually want the warning
              windowed = true,
              compress = true,
              target_arch = Sys.ARCH,
              predicate = Symbol(""),
              parameters = Dict("WINDOWED" => windowed, "PUBLISHER" => publisher)
              )
    
    return MSIX(icon, appxmanifest, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths, selfsign, publisher, pfx_cert, windowed, compress, target_arch, predicate, parameters)
end


"""
    MSIX(overlay; kwargs...)

Create an MSIX configuration object from a project overlay directory.

This constructor creates an MSIX configuration by searching for customization files in the overlay
directory and extracting application parameters from Project.toml. It searches in the overlay directory,
overlay/meta subdirectory, and falls back to default recipes.

# Arguments
- `overlay`: Path to the project overlay directory containing Project.toml

# Keyword Arguments
- `kwargs...`: Additional keyword arguments to override default settings (see main MSIX constructor)

# Examples
```julia
# Create MSIX config from project directory
msix = MSIX(app_dir)

# Create with custom overrides
msix = MSIX(app_dir; skip_long_paths = true)
```
"""
function MSIX(overlay; kwargs...)
    
    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    msix = MSIX(; prefix, kwargs...)
    get_bundle_parameters!(msix.parameters, joinpath(overlay, "Project.toml"))

    return msix
end

function normalize_publisher(publisher)
    items = split(publisher, ",")
    stripped_items = strip.(items)
    return join(items, ", ")
end

# function get_publisher(pfx_cert, selfsign; password="")

#     publisher = @load_preference("publisher", nothing)

#     if !isnothing(publisher)
#         return publisher |> normalize_publisher
#     else
#         if isnothing(pfx_cert) || selfsign
#             return "O=PeaceFounder,C=XX,CN=AppBundler" |> normalize_publisher # order is important
#         else
#             try
#                 return MSIXPack.extract_subject_from_certificate(pfx_cert) |> normalize_publisher
#             catch
#                 error("Extracting publisher from $pfx_cert failed. To sidestep this issue set `publisher` in LocalPrefereces.toml")
#             end
#         end
#     end
# end


"""
    Snap(; prefix, icon, snap_config, desktop_launcher, configure_hook, parameters)

Create a Snap configuration object for Linux application packaging.

This constructor initializes a Snap configuration with paths to required Linux Snap packaging files
including metadata, desktop integration, and optional configuration hooks.

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["snap/icon.png", "icon.png"])`: Path to application icon file
- `snap_config = get_path(prefix, "snap/snap.yaml")`: Path to Snap package metadata template
- `desktop_launcher = get_path(prefix, "snap/main.desktop")`: Path to desktop entry file template for GUI integration
- `configure_hook = get_path(prefix, "snap/configure.sh")`: Path to configuration hook script for runtime config changes
- `parameters = Dict()`: Dictionary of parameters for template rendering (e.g., APP_NAME, APP_VERSION)

# Examples
```julia
# Create Snap config with default recipes
snap = Snap()

# Create Snap config from project overlay
snap = Snap(app_dir)

# Create Snap config with custom settings
snap = Snap(
    icon = "custom_icon.png",
    configure_hook = "my_configure.sh"
)

# Create Snap config with multiple search directories
snap = Snap(
    prefix = ["custom/", "defaults/", "recipes/"]
)
```
"""
struct Snap # by extensions files could have multiple modes that are set via stage command
    icon::String
    snap_config::String
    desktop_launcher::String
    configure_hook::Union{String, Nothing} # needs to be enabled when staging
    windowed::Bool
    compress::Bool
    arch::Symbol
    predicate::Symbol
    parameters::Dict{String, Any}
end

function Snap(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              icon = get_path(prefix, ["snap/icon.png", "icon.png"]),
              snap_config = get_path(prefix, "snap/snap.yaml"),
              desktop_launcher = get_path(prefix, "snap/main.desktop"),
              configure_hook = get_path(prefix, "snap/configure.sh"),
              windowed = true,
              compress = true,
              arch = Sys.ARCH,
              predicate = Symbol(""),
              parameters = Dict("WINDOWED" => windowed)
              )

    return Snap(icon, snap_config, desktop_launcher, configure_hook, windowed, compress, arch, predicate, parameters)
end

"""
    Snap(overlay; kwargs...)

Create a Snap configuration object from a project overlay directory.

This constructor creates a Snap configuration by searching for customization files in the overlay
directory and extracting application parameters from Project.toml. It searches in the overlay directory,
overlay/meta subdirectory, and falls back to default recipes.

# Arguments
- `overlay`: Path to the project overlay directory containing Project.toml

# Keyword Arguments
- `kwargs...`: Additional keyword arguments to override default settings (see main Snap constructor)

# Examples
```julia
# Create Snap config from project directory
snap = Snap(app_dir)

# Create with custom overrides
snap = Snap(app_dir; icon = "custom_icon.png")
```
"""
function Snap(overlay; kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    snap = Snap(; prefix, kwargs...)
    parameters = get_bundle_parameters!(snap.parameters, joinpath(overlay, "Project.toml"))

    return snap
end

# TODO: mention that application needs to be notarized by Apple. That can be done outside the build process by stapling already signed DMG archive. 

"""
    DMG(; prefix, icon, info_config, entitlements, dsstore, pfx_cert, parameters)

Create a DMG configuration object for macOS application packaging.

This constructor initializes a DMG configuration with paths to required macOS packaging files
including icons, property lists, entitlements, and optional code signing certificates.

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"])`: Path to application icon (.icns or .png)
- `info_config = get_path(prefix, "dmg/Info.plist")`: Path to Info.plist template with app metadata
- `entitlements = get_path(prefix, "dmg/Entitlements.plist")`: Path to entitlements file for code signing
- `dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"])`: Path to DS_Store file or template for Finder appearance
- `pfx_cert = get_path(prefix, "dmg/certificate.pfx")`: Path to code signing certificate (optional)
- `parameters = Dict()`: Dictionary of parameters for template rendering (e.g., APP_NAME, APP_VERSION)

# Examples
```julia
# Create DMG config with default recipes
dmg = DMG()

# Create DMG config from project overlay
dmg = DMG(app_dir)

# Create DMG config with custom settings
dmg = DMG(
    icon = "custom_icon.icns",
    entitlements = "custom_entitlements.plist"
)

# Create DMG config with multiple search directories
dmg = DMG(
    prefix = ["custom/", "defaults/", "recipes/"]
)
```
"""
struct DMG
    icon::String
    info_config::String
    entitlements::String
    dsstore::String # if it's toml then use it as source for parsing
    selfsign::Bool
    pfx_cert::Union{String, Nothing}
    shallow_signing::Bool
    hardened_runtime::Bool
    sandboxed_runtime::Bool
    main_redirect::Bool
    hfsplus::Bool
    windowed::Bool
    compress::Bool
    compression::Symbol
    arch::Symbol
    predicate::Symbol # Can be a type
    parameters::Dict{String, Any}
end

# soft link can be used in case one needs to use png source. The issue here is of communicating intent.
function DMG(;
             prefix = joinpath(dirname(@__DIR__), "recipes"),
             icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"]),
             info_config = get_path(prefix, "dmg/Info.plist"),
             entitlements = get_path(prefix, "dmg/Entitlements.plist"),
             dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"]),
             selfsign = false,
             pfx_cert = get_path(prefix, "dmg/certificate.pfx"),
             shallow_signing = @load_preference("dmg_shallow_signing"),
             hardened_runtime = @load_preference("dmg_hardened_runtime"),
             sandboxed_runtime = @load_preference("dmg_sandboxed_runtime"),
             main_redirect = true,
             hfsplus = false,
             windowed = true,
             compress = true,
             compression = :lzma,
             arch = Sys.ARCH,
             predicate = Symbol(""),
             parameters = Dict("WINDOWED" => windowed, "SANDBOXED_RUNTIME" => string(sandboxed_runtime))
             )

    return DMG(icon, info_config, entitlements, dsstore, selfsign, pfx_cert, shallow_signing, hardened_runtime, sandboxed_runtime, main_redirect, hfsplus, windowed, compress, compression, arch, predicate, parameters)
end

"""
    DMG(overlay; kwargs...)

Create a DMG configuration object from a project overlay directory.

This constructor creates a DMG configuration by searching for customization files in the overlay
directory and extracting application parameters from Project.toml. It searches in the overlay directory,
overlay/meta subdirectory, and falls back to default recipes.

# Arguments
- `overlay`: Path to the project overlay directory containing Project.toml

# Keyword Arguments
- `kwargs...`: Additional keyword arguments to override default settings (see main DMG constructor)

# Examples
```julia
# Create DMG config from project directory
dmg = DMG(app_dir)

# Create with custom overrides
dmg = DMG(app_dir; icon = "custom_icon.icns")
```
"""
function DMG(overlay; kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    dmg = DMG(; prefix, kwargs...)
    get_bundle_parameters!(dmg.parameters, joinpath(overlay, "Project.toml"))
    
    return dmg
end

"""
    stage(msix::MSIX, destination::String)

Stage MSIX metadata and structure files into the destination directory.

This function prepares the MSIX package structure by copying or generating the required metadata files,
including application icons, manifest, resources, and installer data.

# Arguments
- `msix::MSIX`: MSIX configuration object containing paths to source files and parameters
- `destination::String`: Target directory where MSIX structure will be created

# Staged Files
- `Assets/`: Application icons (generated from source icon or copied if directory)
- `AppxManifest.xml`: Rendered application manifest with parameters
- `resources.pri`: Package resource index
- `Msix.AppInstaller.Data/MSIXAppInstallerData.xml`: Rendered installer configuration

# Examples
```julia
msix = MSIX(app_dir)
stage(msix, "build/msix_staging")
```
"""
function stage(msix::MSIX, destination::String)

    if !isdir(destination)
        mkdir(destination)
    end

    if isdir(msix.icon)
        @info "Treating icon path as assets directory"
        cp(msix.icon, joinpath(destination, "Assets"))
    else
        MSIXIcons.generate_app_icons(msix.icon, joinpath(destination, "Assets")) 
    end

    (; predicate, parameters) = msix
    install(msix.appxmanifest, joinpath(destination, "AppxManifest.xml"); parameters, predicate)
    cp(msix.resources_pri, joinpath(destination, "resources.pri"))
    install(msix.msixinstallerdata, joinpath(destination, "Msix.AppInstaller.Data/MSIXAppInstallerData.xml"); parameters)

    return
end

function install_dsstore(source::String, dsstore_destination::String; parameters = Dict())

    rm(dsstore_destination; force=true)

    if last(splitext(source)) == ".toml"

        dsstore_toml = Mustache.render(read(source, String), parameters)
        dsstore = TOML.parse(dsstore_toml)

        DSStore.open_dsstore(dsstore_destination, "w+") do ds

            ds[".", "icvl"] = ("type", "icnv")
            ds[".", "vSrn"] = ("long", 1)

            for file_key in keys(dsstore)
                file_dict = dsstore[file_key]
                for entry_key in keys(file_dict)
                    ds[file_key, entry_key] = file_dict[entry_key]
                end
            end
        end
        
    else
        cp(source, dsstore_destination)
    end

    return
end

function retrieve_macos_launcher(platform::MacOS)

    artifacts_toml = joinpath(dirname(dirname(pathof(AppBundlerUtils_jll))), "Artifacts.toml")
    artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]

    try 

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache()

        hash = artifacts["git-tree-sha1"]
        Pkg.Artifacts.ensure_artifact_installed("AppBundlerUtils", artifacts, artifacts_toml) 

        return joinpath(artifacts_cache(), hash, "bin", "macos_launcher")

    finally
        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = nothing
    end

    return
end

"""
    stage(dmg::DMG, destination::String; dsstore = false, main_redirect = false, arch = :x86_64)

Stage DMG metadata and macOS app bundle structure into the destination directory.

This function prepares the macOS .app bundle structure by installing the icon, Info.plist, and
optionally a native launcher executable. When creating a DMG, it can also set up the custom
Finder appearance with .DS_Store and Applications symlink.

# Arguments
- `dmg::DMG`: DMG configuration object containing paths to source files and parameters
- `destination::String`: Target directory for the .app bundle (e.g., "MyApp.app")

# Keyword Arguments
- `dsstore = false`: If `true`, creates .DS_Store and Applications symlink in parent directory for DMG appearance
- `main_redirect = false`: If `true`, installs a native launcher that redirects to the Julia executable
- `arch = :x86_64`: Target architecture (`:x86_64` or `:arm64`) for the native launcher binary

# Staged Files
- `Contents/Resources/icon.icns`: Application icon
- `Contents/Info.plist`: Rendered application metadata
- `Contents/MacOS/<app-name>` (optional): Native launcher if `main_redirect=true`

When `dsstore=true`, additionally creates in parent directory:
- `Applications` symlink to /Applications
- `.DS_Store` with custom Finder appearance settings

# Examples
```julia
dmg = DMG(app_dir)
stage(dmg, "MyApp.app"; dsstore = true, main_redirect = true, arch = :arm64)
```
"""
function stage(dmg::DMG, destination::String; dsstore = false) 

    (; predicate, parameters) = dmg
    app_name = parameters["APP_NAME"]

    install(dmg.icon, joinpath(destination, "Contents/Resources/icon.icns"))
    install(dmg.info_config, joinpath(destination, "Contents/Info.plist"); parameters, predicate)

    if dmg.main_redirect
        launcher = retrieve_macos_launcher(MacOS(dmg.arch))
        install(launcher, joinpath(destination, "Contents/MacOS/$app_name"); executable = true)
    end

    if dsstore
        symlink("/Applications", joinpath(dirname(destination), "Applications"); dir_target=true)
        install_dsstore(dmg.dsstore, joinpath(dirname(destination), ".DS_Store"); parameters)
    end

    return
end

"""
    stage(snap::Snap, destination::String; install_configure = false)

Stage Snap metadata and structure files into the destination directory.

This function prepares the Snap package structure by installing the required metadata files,
including the icon, snap.yaml configuration, desktop launcher, and optionally a configuration hook.

# Arguments
- `snap::Snap`: Snap configuration object containing paths to source files and parameters
- `destination::String`: Target directory where Snap structure will be created

# Keyword Arguments
- `install_configure = false`: If `true`, installs the configure hook script for runtime configuration

# Staged Files
- `meta/icon.png`: Application icon
- `meta/snap.yaml`: Rendered Snap package metadata and configuration
- `meta/gui/<app-name>.desktop`: Rendered desktop launcher for GUI integration
- `meta/hooks/configure` (optional): Configuration hook script if `install_configure=true`

# Examples
```julia
snap = Snap(app_dir)
stage(snap, "build/snap_staging"; install_configure = true)
```
"""
function stage(snap::Snap, destination::String)

    (; predicate, parameters) = snap
    app_name = parameters["APP_NAME"]

    install(snap.icon, joinpath(destination, "meta/icon.png"))
    install(snap.snap_config, joinpath(destination, "meta/snap.yaml"); parameters, predicate)
    install(snap.desktop_launcher, joinpath(destination, "meta/gui/$app_name.desktop"); parameters, predicate)
    
    if !isnothing(snap.configure_hook)
        install(snap.configure_hook, joinpath(destination, "meta/hooks/configure"); parameters, executable = true, predicate)
    end

    return
end

"""
    bundle(setup::Function, dmg::DMG, destination::String; compress::Bool = isext(destination, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), main_redirect = false, arch = :x86_64)

Create a macOS application bundle or DMG disk image with automatic code signing and customizable setup.

This function provides a flexible way to create macOS applications. It first stages the DMG metadata 
and structure, then accepts a custom setup function that defines how the application should be prepared, 
and finally handles code signing and optionally packages the result into a distributable DMG installer 
with custom appearance settings.

# Arguments
- `setup::Function`: A function that takes the staging directory path as an argument and performs 
  the necessary application setup (typically called from `build_app` to bundle the Julia application)
- `dmg::DMG`: A DMG configuration object containing icon, entitlements, signing certificate, and other metadata
- `destination::String`: Path where the final .app bundle or .dmg disk image should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".dmg")`: Whether to compress into a DMG. Defaults to `true` if 
  destination has .dmg extension, otherwise creates standalone .app bundle
- `compression = :lzma`: Compression algorithm for DMG creation (`:lzma`, `:bzip2`, `:zlib`, or `:lzfse`)
- `force = false`: If `true`, overwrites existing destination. Otherwise throws an error if destination exists
- `password = get(ENV, "MACOS_PFX_PASSWORD", "")`: Password for the code signing certificate
- `main_redirect = false`: If `true`, installs a native launcher that redirects to the main Julia executable
- `arch = :x86_64`: Target architecture (`:x86_64` or `:arm64`) for the launcher binary

# DMG Structure

The staging directory creates a macOS .app bundle structure:
- `Contents/Resources/icon.icns`: Application icon
- `Contents/Info.plist`: Application metadata and configuration
- `Contents/MacOS/<app-name>` (optional): Native launcher executable if `main_redirect=true`

When `compress=true`, additional DMG-specific files are created in a parent directory of `staging_dir`:
- `Applications` symlink: Link to /Applications for drag-and-drop installation
- `.DS_Store`: Custom Finder window appearance settings

# Code Signing

The function automatically handles code signing for all created applications. If a signing certificate is 
provided in the DMG configuration (typically at `meta/macos/certificate.pfx`), it will be used along with 
the password from the `MACOS_PFX_PASSWORD` environment variable. When no certificate is available, the 
function generates and uses a temporary self-signed certificate for signing.

Custom entitlements can be specified in the DMG configuration. If not provided, default entitlements 
appropriate for most applications will be used automatically.

# Examples
```julia
dmg = DMG(app_dir)
bundle(dmg, "MyApp.dmg"; compress = true, compression = :lzma) do staging_dir
    # Compile application files into staging_dir that will be included in the bundle
end
```
"""
function bundle(setup::Function, dmg::DMG, destination::String; force = false, password = "") 

    (; parameters, predicate) = dmg
    
    installer_title = join([parameters["APP_DISPLAY_NAME"], "Installer"], " ")

    if length(installer_title) > 32
        error("Installer title \"$installer_title\" exceeds the maximum 32 characters allowed by xorriso (current length: $(length(installer_title))). Please shorten APP_DISPLAY_NAME to $(32 - length(" Installer")) characters or less.")
    end

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    @info "Initializing DMG staging layout..."
    if dmg.compress
        #appname = parameters["APP_NAME"]
        appname = parameters["APP_DISPLAY_NAME"]
        app_stage = joinpath(mktempdir(), "$appname.app")
        stage(dmg, app_stage; dsstore = true)        
    else
        app_stage = destination
        stage(dmg, app_stage; dsstore = false)
    end

    @info "Installing app into staging area..."
    setup(app_stage)

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

    if dmg.selfsign
        @info "Generating self signing certificate"
        pfx_path = joinpath(tempdir(), "certificate.pfx")
        DMGPack.generate_self_signing_pfx(pfx_path; password = "")        
    else
        pfx_path = dmg.pfx_cert
    end        

    @info "Packaging staging area into DMG..."
    entitlements = joinpath(mktempdir(), "Entitlements.plist")
    install(dmg.entitlements, entitlements; parameters, predicate)
    
    DMGPack.pack(app_stage, destination, entitlements; pfx_path, password, compression = dmg.compress ? dmg.compression : nothing, installer_title, shallow_signing = dmg.shallow_signing, hardened_runtime = dmg.hardened_runtime, hfsplus = dmg.hfsplus)

    return
end

"""
    bundle(setup::Function, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), force = false, password = get(ENV, "WINDOWS_PFX_PASSWORD", ""))

Create a Windows MSIX installer with automatic code signing and customizable setup.

This function creates a Windows MSIX installer by first staging the MSIX metadata and structure, 
then running a setup function to prepare the application staging directory, and finally optionally 
compressing it into a distributable MSIX package with code signing.

# Arguments
- `setup::Function`: A function that takes the staging directory path as an argument and performs 
  the necessary setup (typically bundling the Julia application and its dependencies)
- `msix::MSIX`: An MSIX configuration object containing app icons, manifest, resources, signing certificate, 
  path length settings, and other metadata
- `destination::String`: Path where the final application directory or MSIX package should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".msix")`: Whether to compress the application into an MSIX package.
  Defaults to `true` if the destination has a .msix extension, otherwise `false` (creates directory structure only)
- `force = false`: If `true`, overwrites existing destination. Otherwise throws an error if destination exists
- `password = get(ENV, "WINDOWS_PFX_PASSWORD", "")`: Password for the code signing certificate

# MSIX Structure

The staging directory includes:
- `Assets/`: Application icons in various sizes (or copied directly if icon path is a directory)
- `AppxManifest.xml`: MSIX application manifest with package metadata
- `resources.pri`: Package resource index file
- `Msix.AppInstaller.Data/MSIXAppInstallerData.xml`: Installer configuration data

# Code Signing

Code signing is performed automatically if `compress=true`. The signing certificate is specified in the 
MSIX configuration (typically at `meta/msix/certificate.pfx`) and is password-encrypted with the password 
passed via the `WINDOWS_PFX_PASSWORD` environment variable. If a signing certificate is not available, 
a temporary one-time self-signed certificate is generated and used for signing the MSIX installer.

# Path Length Handling

The MSIX configuration includes `path_length_threshold`, `skip_long_paths` and `skip_symlinks` settings to handle Windows' path limitations. Files exceeding the length threshold will either be skipped or cause an error depending on the configuration.

# Examples
```julia
msix = MSIX(app_dir)
bundle(msix, "MyApp.msix"; compress = true) do staging_dir
    # Compile application files into staging_dir that will be included in the bundle
end
```
"""
function bundle(setup::Function, msix::MSIX, destination::String; force = false, password = "")

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end
    app_stage = msix.compress ? mktempdir() : destination

    @info "Initializing MSIX staging layout..."
    stage(msix, app_stage)
    @info "Installing app into staging area..."
    setup(app_stage)

    (; path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths) = msix
    ensure_windows_compatability(app_stage; path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths)

    if msix.compress
        if msix.selfsign
            @info "Generating self signing certificate"
            pfx_path = joinpath(tempdir(), "certificate.pfx")
            MSIXPack.generate_self_signed_certificate(pfx_path; password, publisher = msix.publisher)
        else
            pfx_path = msix.pfx_cert
        end        
        @info "Packaging staging area into MSIX..."
        MSIXPack.pack(app_stage, destination; pfx_path, password)        
    end
    
    return
end


"""
    bundle(setup::Function, snap::Snap, destination::String; compress::Bool = isext(destination, ".snap"), force = false, install_configure = false)

Create a Linux Snap package with customizable setup and configuration hooks.

This function creates a Linux Snap package by first staging the Snap metadata and structure, 
then running a setup function to prepare the application staging directory, and finally optionally 
compressing it into a distributable .snap package.

# Arguments
- `setup::Function`: A function that takes the staging directory path as an argument and performs 
  the necessary setup (typically bundling the Julia application and its dependencies)
- `snap::Snap`: A Snap configuration object containing app icon, snap.yaml configuration, desktop launcher, configure hook script, and other metadata
- `destination::String`: Path where the final application directory or .snap package should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".snap")`: Whether to compress the application into a .snap package.
  Defaults to `true` if the destination has a .snap extension, otherwise `false` (creates directory structure only)
- `force = false`: If `true`, overwrites existing destination. Otherwise throws an error if destination exists
- `install_configure = false`: If `true`, installs the configure hook script that runs when snap configuration 
  changes. This allows the application to respond to user configuration via `snap set/get` commands

# Snap Structure

The staging directory is created with proper permissions (0o755) and includes:
- `meta/snap.yaml`: Snap package metadata and configuration
- `meta/icon.png`: Application icon
- `meta/gui/<app-name>.desktop`: Desktop launcher file for GUI integration
- `meta/hooks/configure` (optional): Configuration hook script if `install_configure=true`

# Examples
```julia
snap = Snap(app_dir)
bundle(snap, "MyApp.snap"; compress = true) do staging_dir
    # Compile application files into staging_dir that will be included in the bundle
end
```
"""
function bundle(setup::Function, snap::Snap, destination::String; force = false)

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = snap.compress ? mktempdir() : destination

    @info "Initializing Snap staging layout..."
    stage(snap, app_stage)    
    @info "Installing app into staging area..."
    setup(app_stage)

    if snap.compress
        @info "Packaging staging area into Snap..."
        SnapPack.pack(app_stage, destination)
    end

    return
end
