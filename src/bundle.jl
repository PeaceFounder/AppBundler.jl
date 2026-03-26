import Pkg, Artifacts
using Pkg.BinaryPlatforms: MacOS
using AppBundlerUtils_jll
using Preferences
import Mustache


"""
    MSIX([overlay]; arch, compress, windowed, kwargs...)
 
Create an MSIX configuration object for Windows application packaging.
 
When `overlay` is provided, configuration files are searched in `overlay`, then `overlay/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `overlay/Project.toml`, and packaging defaults (`path_length_threshold`, `selfsign`,
etc.) are read from `overlay/LocalPreferences.toml`. Without `overlay`, only the built-in recipes
and the active project's `LocalPreferences.toml` are used.
 
# Arguments
- `overlay`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/msix/` overrides
 
# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true)`: Path to application icon file or Assets directory
- `appxmanifest = get_path(prefix, "msix/AppxManifest.xml")`: Path to MSIX application manifest template
- `resources_pri = get_path(prefix, "msix/resources.pri")`: Path to package resource index file
- `msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml")`: Path to installer configuration template
- `path_length_threshold`: Maximum allowed path length; defaults to `msix_path_length_threshold` preference
- `skip_long_paths`: If `true`, skip files exceeding path length threshold; if `false`, throw an error; defaults to `msix_skip_long_paths` preference
- `skip_symlinks`: If `true`, skip file and directory symlinks; defaults to `msix_skip_symlinks` preference
- `skip_unicode_paths`: If `true`, skip files with non-ASCII paths; defaults to `msix_skip_unicode_paths` preference
- `selfsign`: If `true`, generate a temporary self-signed certificate instead of using `pfx_cert`; defaults to `selfsign` preference
- `publisher`: Publisher string embedded in the manifest; defaults to `msix_publisher` preference
- `pfx_cert = get_path(prefix, "msix/certificate.pfx")`: Path to code signing certificate
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into an `.msix` archive; defaults to `compress` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `overlay` is provided, pre-populated from `Project.toml` and preferences: `APP_NAME`, `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`, `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, `MODULE_NAME` (Julia-based bundles only), `WINDOWED`, and `PUBLISHER`
 
# Examples
```julia
MSIX()                                    # default recipes only
MSIX(app_dir)                             # overlay with Project.toml parameters
MSIX(app_dir; skip_long_paths = true)     # overlay with keyword overrides
MSIX(; prefix = ["custom/", "recipes/"]) # explicit search path
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
    predicate::String
    parameters::Dict{String, Any}
end

function MSIX(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              preferences = preferences(),
              icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true),
              appxmanifest = get_path(prefix, "msix/AppxManifest.xml"),
              resources_pri = get_path(prefix, "msix/resources.pri"),
              msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml"),
              path_length_threshold = preferences["msix_path_length_threshold"],
              skip_long_paths = preferences["msix_skip_long_paths"],
              skip_symlinks = preferences["msix_skip_symlinks"],
              skip_unicode_paths = preferences["msix_skip_unicode_paths"],
              selfsign = preferences["selfsign"],              
              publisher = preferences["msix_publisher"] |> normalize_publisher,   #get_publisher(pfx_cert, selfsign),
              pfx_cert = get_path(prefix, "msix/certificate.pfx"), # We actually want the warning
              windowed = preferences["windowed"],
              compress = preferences["compress"],
              arch = Sys.ARCH,
              predicate = preferences["bundler"],
              parameters = Dict("WINDOWED" => windowed, "PUBLISHER" => publisher)
              )
    
    return MSIX(icon, appxmanifest, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths, selfsign, publisher, pfx_cert, windowed, compress, arch, predicate, parameters)
end

function MSIX(overlay; preferences = preferences(), kwargs...)
    
    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    msix = MSIX(; prefix, preferences, kwargs...)
    get_bundle_parameters!(msix.parameters, joinpath(overlay, "Project.toml"); preferences)

    return msix
end

function normalize_publisher(publisher)
    items = split(replace(publisher, " "=>""), ",")
    stripped_items = strip.(items)
    return join(items, ", ")
end

"""
    Snap([overlay]; arch, compress, windowed, kwargs...)
 
Create a Snap configuration object for Linux application packaging.
 
When `overlay` is provided, configuration files are searched in `overlay`, then `overlay/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `overlay/Project.toml`, and packaging defaults (`windowed`, `compress`, etc.) are read
from `overlay/LocalPreferences.toml`. Without `overlay`, only the built-in recipes and the active
project's `LocalPreferences.toml` are used.
 
# Arguments
- `overlay`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/snap/` overrides
 
# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["snap/icon.png", "icon.png"])`: Path to application icon file
- `snap_config = get_path(prefix, "snap/snap.yaml")`: Path to Snap package metadata template
- `desktop_launcher = get_path(prefix, "snap/main.desktop")`: Path to desktop entry file template for GUI integration
- `configure_hook`: Path to configuration hook script run on `snap set`; resolved from prefix using the bundler predicate; omitted if not found
- `main_launcher`: Path to main launcher script installed into `bin/`; resolved from prefix using the bundler predicate; omitted if not found
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into a `.snap` archive; defaults to `compress` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `overlay` is provided, pre-populated from `Project.toml` and preferences: `APP_NAME`, `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`, `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, `MODULE_NAME` (Julia-based bundles only), and `WINDOWED`
 
# Examples
```julia
Snap()                                    # default recipes only
Snap(app_dir)                             # overlay with Project.toml parameters
Snap(app_dir; windowed = false)           # overlay with keyword overrides
Snap(; prefix = ["custom/", "recipes/"]) # explicit search path
```
"""
struct Snap # by extensions files could have multiple modes that are set via stage command
    icon::String
    snap_config::String
    desktop_launcher::String
    configure_hook::Union{String, Nothing} # needs to be enabled when staging
    main_launcher::Union{String, Nothing}
    windowed::Bool
    compress::Bool
    arch::Symbol
    predicate::String
    parameters::Dict{String, Any}
end


function Snap(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              preferences = preferences(),
              predicate = preferences["bundler"],
              icon = get_path(prefix, ["snap/icon.png", "icon.png"]),
              snap_config = get_path(prefix, "snap/snap.yaml"),
              desktop_launcher = get_path(prefix, "snap/main.desktop"),
              configure_hook = get_path(prefix, hook("snap/configure.sh", predicate); warn = false),
              main_launcher = get_path(prefix, hook("snap/main.sh", predicate); warn = false),
              windowed = preferences["windowed"],
              compress = preferences["compress"],
              arch = Sys.ARCH,
              parameters = Dict("WINDOWED" => windowed)
              )

    return Snap(icon, snap_config, desktop_launcher, configure_hook, main_launcher, windowed, compress, arch, predicate, parameters)
end

function Snap(overlay; preferences = preferences(), kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    snap = Snap(; prefix, preferences, kwargs...)
    parameters = get_bundle_parameters!(snap.parameters, joinpath(overlay, "Project.toml"); preferences)

    return snap
end

# TODO: mention that application needs to be notarized by Apple. That can be done outside the build process by stapling already signed DMG archive. 

"""
    DMG([overlay]; arch, compress, windowed, kwargs...)
 
Create a DMG configuration object for macOS application packaging.
 
When `overlay` is provided, configuration files are searched in `overlay`, then `overlay/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `overlay/Project.toml`, and packaging defaults (`selfsign`, `compression`, etc.) are
read from `overlay/LocalPreferences.toml`. Without `overlay`, only the built-in recipes and the
active project's `LocalPreferences.toml` are used.
 
# Arguments
- `overlay`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/dmg/` overrides
 
# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"])`: Path to application icon (.icns or .png)
- `info_config = get_path(prefix, "dmg/Info.plist")`: Path to Info.plist template with app metadata
- `entitlements = get_path(prefix, "dmg/Entitlements.plist")`: Path to entitlements file for code signing
- `dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"])`: Path to DS_Store file or TOML template for Finder window appearance
- `selfsign`: If `true`, generate a temporary self-signed certificate instead of using `pfx_cert`; defaults to `selfsign` preference
- `pfx_cert = get_path(prefix, "dmg/certificate.pfx")`: Path to code signing certificate
- `shallow_signing`: If `true`, sign only the top-level bundle rather than all nested binaries; defaults to `dmg_shallow_signing` preference
- `hardened_runtime`: If `true`, enable hardened runtime during signing (required for notarization); defaults to `dmg_hardened_runtime` preference
- `sandboxed_runtime`: If `true`, enable the App Sandbox entitlement; defaults to `dmg_sandboxed_runtime` preference
- `main_launcher`: Path to the Julia entry-point script. When set, a native redirect launcher is installed at `Contents/MacOS/<app_name>` and the script itself at `Contents/Libraries/main`; resolved from prefix using the bundler predicate; omitted if not found
- `hfsplus = false`: If `true`, use HFS+ filesystem when building the disk image otherwise uses ISO
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into a `.dmg` disk image; defaults to `compress` preference
- `compression`: Compression algorithm for the disk image (`:lzma`, `:bzip2`, `:zlib`, or `:lzfse`); defaults to `dmg_compression` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `overlay` is provided, pre-populated from `Project.toml` and preferences: `APP_NAME`, `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`, `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, `MODULE_NAME` (Julia-based bundles only), `WINDOWED`, and `SANDBOXED_RUNTIME`
 
# Examples
```julia
DMG()                                    # default recipes only
DMG(app_dir)                             # overlay with Project.toml parameters
DMG(app_dir; hardened_runtime = false)   # overlay with keyword overrides
DMG(; prefix = ["custom/", "recipes/"]) # explicit search path
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
    main_launcher::Union{String, Nothing}
    hfsplus::Bool
    windowed::Bool
    compress::Bool
    compression::Symbol
    arch::Symbol
    predicate::String
    parameters::Dict{String, Any}
end

# soft link can be used in case one needs to use png source. The issue here is of communicating intent.
function DMG(;
             prefix = joinpath(dirname(@__DIR__), "recipes"),
             preferences = preferences(),
             predicate = preferences["bundler"],
             icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"]),
             info_config = get_path(prefix, "dmg/Info.plist"),
             entitlements = get_path(prefix, "dmg/Entitlements.plist"),
             dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"]),
             selfsign = preferences["selfsign"],
             pfx_cert = get_path(prefix, "dmg/certificate.pfx"),
             shallow_signing = preferences["dmg_shallow_signing"],
             hardened_runtime = preferences["dmg_hardened_runtime"],
             sandboxed_runtime = preferences["dmg_sandboxed_runtime"],
             #main_redirect = true,
             main_launcher = get_path(prefix, hook("dmg/main.sh", predicate); warn = false),
             hfsplus = false,
             windowed = preferences["windowed"],
             compress = preferences["compress"],
             compression = preferences["dmg_compression"] |> Symbol,
             arch = Sys.ARCH,
             parameters = Dict("WINDOWED" => windowed, "SANDBOXED_RUNTIME" => string(sandboxed_runtime))
             )

    return DMG(icon, info_config, entitlements, dsstore, selfsign, pfx_cert, shallow_signing, hardened_runtime, sandboxed_runtime, main_launcher, hfsplus, windowed, compress, compression, arch, predicate, parameters)
end

function DMG(overlay; preferences = preferences(), kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    dmg = DMG(; prefix, preferences, kwargs...)
    get_bundle_parameters!(dmg.parameters, joinpath(overlay, "Project.toml"); preferences)
    
    return dmg
end


"""
    stage(config, destination::String; kwargs...)
 
Stage package metadata and directory structure into `destination` in preparation for bundling.
 
`config` is a format-specific configuration object — [`MSIX`](@ref), [`DMG`](@ref), or
[`Snap`](@ref) — that carries the template files, parameters, and settings for the target
platform. Mustache-rendered templates are written using the parameters stored in `config`.
 
`stage` is called automatically by [`bundle`](@ref), but can be used directly when you need
to inspect or modify the staging directory before compression and signing.
 
## Staged layout by format
 
**MSIX** (`stage(msix::MSIX, destination)`)
- `Assets/` — application icons (generated from source or copied verbatim if already a directory)
- `AppxManifest.xml` — rendered package manifest
- `resources.pri` — package resource index
- `Msix.AppInstaller.Data/MSIXAppInstallerData.xml` — rendered installer configuration
 
**DMG** (`stage(dmg::DMG, destination; dsstore = false)`)
- `Contents/Resources/icon.icns` — application icon
- `Contents/Info.plist` — rendered application metadata
- `Contents/MacOS/<app-name>` (optional) — native launcher when `main_launcher` is set
 
  When `dsstore = true`, also writes into the *parent* of `destination`:
  - `Applications` — symlink to `/Applications` for drag-and-drop installation
  - `.DS_Store` — custom Finder window appearance
 
**Snap** (`stage(snap::Snap, destination)`)
- `meta/icon.png` — application icon
- `meta/snap.yaml` — rendered Snap package metadata
- `meta/gui/<app-name>.desktop` — rendered desktop launcher
- `meta/hooks/configure` (optional) — configuration hook when `configure_hook` is set
- `bin/<app-name>` (optional) — main launcher script when `main_launcher` is set
 
# Examples
```julia
stage(MSIX(app_dir), "build/msix_staging")
stage(DMG(app_dir),  "build/MyApp.app"; dsstore = true)
stage(Snap(app_dir), "build/snap_staging")
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

function stage(dmg::DMG, destination::String; dsstore = false) 

    (; predicate, parameters) = dmg
    app_name = parameters["APP_NAME"]

    install(dmg.icon, joinpath(destination, "Contents/Resources/icon.icns"))
    install(dmg.info_config, joinpath(destination, "Contents/Info.plist"); parameters, predicate)

    # if dmg.main_redirect
    #     launcher = retrieve_macos_launcher(MacOS(dmg.arch))
    #     install(launcher, joinpath(destination, "Contents/MacOS/$app_name"); executable = true)
    # end

    if dsstore
        symlink("/Applications", joinpath(dirname(destination), "Applications"); dir_target=true)
        install_dsstore(dmg.dsstore, joinpath(dirname(destination), ".DS_Store"); parameters)
    end

    if !isnothing(dmg.main_launcher)
        launcher = retrieve_macos_launcher(MacOS(dmg.arch))
        install(launcher, joinpath(destination, "Contents/MacOS/$app_name"); executable = true)

        install(dmg.main_launcher, joinpath(destination, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true, predicate = dmg.predicate)
    end

    return
end

function stage(snap::Snap, destination::String)

    (; predicate, parameters) = snap
    app_name = parameters["APP_NAME"]

    install(snap.icon, joinpath(destination, "meta/icon.png"))
    install(snap.snap_config, joinpath(destination, "meta/snap.yaml"); parameters, predicate)
    install(snap.desktop_launcher, joinpath(destination, "meta/gui/$app_name.desktop"); parameters, predicate)
    
    if !isnothing(snap.configure_hook)
        install(snap.configure_hook, joinpath(destination, "meta/hooks/configure"); parameters, executable = true, predicate)
    end

    if !isnothing(snap.main_launcher)
        app_name = snap.parameters["APP_NAME"]
        install(snap.main_launcher, joinpath(destination, "bin/$app_name"); parameters, executable = true, predicate)
    end

    return
end


"""
    bundle(setup::Function, config, destination::String; force = false, kwargs...)
 
Stage, populate, and optionally compress an application bundle for distribution.
 
`config` is a format-specific configuration object — [`MSIX`](@ref) (Windows), [`DMG`](@ref)
(macOS), or [`Snap`](@ref) (Linux) — and `destination` is the path of the final artifact
(e.g. `"MyApp.msix"`, `"MyApp.dmg"`, `"MyApp.snap"`) or an uncompressed staging directory.
 
The function follows three steps:
 
1. **Stage** — writes platform metadata and directory structure into a staging area via
   [`stage`](@ref).
2. **Setup** — calls `setup(staging_dir)`, where you copy or compile the application
   files that should be included in the bundle.
3. **Pack** — when `config.compress` is `true` (the default when `destination` carries the
   format extension), compresses the staging area into the final artifact and performs code
   signing.
 
Set `force = true` to overwrite an existing destination path.
 
## Code signing
 
MSIX and DMG sign the bundle automatically during the pack step. Pass the certificate password
via the `password` keyword argument (defaults to `""`). When `config.selfsign` is `true`, a
temporary self-signed certificate is generated instead of using the one in the configuration.
DMG entitlements are rendered from the template stored in the configuration.
Snap packages are not signed locally; they are verified by the Snap Store after upload.
 
# Examples
```julia
bundle(MSIX(app_dir), "MyApp.msix") do staging_dir
    # copy or compile application files into staging_dir
end
 
bundle(DMG(app_dir), "MyApp.dmg") do staging_dir
    # copy or compile application files into staging_dir
end
 
bundle(Snap(app_dir), "MyApp.snap") do staging_dir
    # copy or compile application files into staging_dir
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
