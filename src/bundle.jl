import Pkg, Artifacts
using Pkg.BinaryPlatforms: MacOS
using AppBundlerUtils_jll
import Mustache

"""
    MSIX([project]; arch, compress, windowed, kwargs...)

Create an MSIX configuration object for Windows application packaging.

When `project` is provided, configuration files are searched in `project`, then `project/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `project/Project.toml`, and packaging defaults (`path_length_threshold`, `selfsign`,
etc.) are read from `project/LocalPreferences.toml`. Without `project`, only the built-in recipes
and the active project's `LocalPreferences.toml` are used.

# Arguments
- `project`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/msix/` overrides

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `preferences`: Dictionary of packaging preferences used for the defaults below; read from `project` when given, otherwise from the active project
- `icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true)`: Path to application icon file or Assets directory
- `appxmanifest = get_path(prefix, "msix/AppxManifest.xml")`: Path to MSIX application manifest template
- `command::Cmd`: Command launching the application; defaults to `msix.command` preference. Its executable and escaped arguments are exposed to the manifest template as `COMMAND_EXE` and `COMMAND_ARGS`
- `resources_pri = get_path(prefix, "msix/resources.pri")`: Path to package resource index file
- `msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml")`: Path to installer configuration template
- `path_length_threshold`: Maximum allowed path length; defaults to `msix.path_length_threshold` preference
- `skip_long_paths`: If `true`, skip files exceeding path length threshold; if `false`, throw an error; defaults to `msix.skip_long_paths` preference
- `skip_symlinks`: If `true`, skip file and directory symlinks; defaults to `msix.skip_symlinks` preference
- `skip_unicode_paths`: If `true`, skip files with non-ASCII paths; defaults to `msix.skip_unicode_paths` preference
- `selfsign`: If `true`, generate a temporary self-signed certificate instead of using `pfx_cert`; defaults to `selfsign` preference
- `publisher`: Publisher string embedded in the manifest (e.g. `"CN=Example, O=Example Ltd"`); defaults to `msix.publisher` preference, normalized to `", "`-separated fields
- `pfx_cert = get_path(prefix, "msix/certificate.pfx")`: Path to code signing certificate; `nothing` when the `skipsign` preference is set
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into an `.msix` archive; defaults to `compress` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. Always contains `WINDOWED`,
  `PUBLISHER`, `COMMAND_EXE` and `COMMAND_ARGS`, derived from the keywords above. When `project` is
  provided, it is further populated from `Project.toml` and preferences: `APP_NAME`,
  `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`,
  `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, and `MODULE_NAME` (Julia-based bundles only)

# Examples
```julia
MSIX()                                    # default recipes only
MSIX(app_dir)                             # project with Project.toml parameters
MSIX(app_dir; skip_long_paths = true)     # project with keyword overrides
MSIX(app_dir; command = `bin\\myapp.exe --flag "a b"`)  # custom launch command
MSIX(; prefix = ["custom/", "recipes/"])  # explicit search path
```
"""
struct MSIX
    icon::String # direcotry reading is something to look into here
    appxmanifest::String 
    command::Cmd
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


"""
    xml_escape_args(args) -> String

Turn an argument list (or a `Cmd`) into a string suitable for an
AppxManifest `Parameters="..."` attribute.
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


function MSIX(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              preferences = preferences(),
              icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true),
              appxmanifest = get_path(prefix, "msix/AppxManifest.xml"),
              command = Cmd(preferences["msix"]["command"]),
              resources_pri = get_path(prefix, "msix/resources.pri"),
              msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml"),
              path_length_threshold = preferences["msix"]["path_length_threshold"],
              skip_long_paths = preferences["msix"]["skip_long_paths"],
              skip_symlinks = preferences["msix"]["skip_symlinks"],
              skip_unicode_paths = preferences["msix"]["skip_unicode_paths"],
              selfsign = preferences["selfsign"],              
              publisher = preferences["msix"]["publisher"] |> normalize_publisher,   #get_publisher(pfx_cert, selfsign),
              pfx_cert = preferences["skipsign"] ? nothing : get_path(prefix, "msix/certificate.pfx"), # We actually want the warning
              windowed = preferences["windowed"],
              compress = preferences["compress"],
              arch = Sys.ARCH,
              predicate = preferences["bundler"],
              parameters = Dict("WINDOWED" => windowed, "PUBLISHER" => publisher, "COMMAND_EXE" => first(command), "COMMAND_ARGS" => xml_escape_args(command))
              )
    
    return MSIX(icon, appxmanifest, command, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths, selfsign, publisher, pfx_cert, windowed, compress, arch, predicate, parameters)

end

function MSIX(project; preferences = get_project_preferences(project), kwargs...)
    
    prefix = [project, joinpath(project, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    msix = MSIX(; prefix, preferences, kwargs...)
    get_bundle_parameters!(msix.parameters, preferences)

    return msix
end

function normalize_publisher(publisher)
    items = split(replace(publisher, " "=>""), ",")
    stripped_items = strip.(items)
    return join(items, ", ")
end



"""
    MSIX2EXE([project]; prefix, preferences, bootstrap, windowed, sfx_stub, title)

Create an MSIX-to-EXE configuration object for creating self-extracting Windows installers from MSIX packages.

The resulting installer is a 7-Zip-based self-extracting executable. When launched, the executable extracts the MSIX package and the configured PowerShell bootstrap script to a temporary directory and then executes the bootstrap script with the extracted MSIX package as its argument.

This is useful for distributing self-signed MSIX packages, since the bootstrap script can extract and install the package's signing certificate in the system's root, before launching installer on the MSIX installer.

When `project` is provided, configuration files are searched in `project`, then `project/meta`, then the built-in recipes directory. Without `project`, only the built-in recipes and the active project's `LocalPreferences.toml` are used.

# Arguments
- `project`: Path to a project directory containing optional `Project.toml`, `LocalPreferences.toml`, and optional `meta/msix/` overrides

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `bootstrap: Path to the bootstrap script which is embedded in the self-extracting installer. The script is invoked with the extracted MSIX package as its first argument
- `windowed = preferences["msix2exe_windowed"]`: If `true`, run the bootstrap process without displaying a console window and launch graphical MSIX installer
- `sfx_stub = get(preferences, "msix2exe_sfx_stub", MSIX2EXEPack.extract_stub())`: Path to the 7-Zip self-extracting executable stub used to construct the installer
- `title = "Installer"`: Title displayed by the self-extracting installer

# Bootstrap Script

The bootstrap script is invoked after the embedded files have been extracted, with the MSIX package path supplied as its first argument. For example:

```powershell
powershell.exe bootstrap.ps1 msix_archive.msix
```
"""
struct MSIX2EXE
    bootstrap::String
    windowed::Bool
    sfx_stub::String # Can be configured via preferences
    title::String
end

function MSIX2EXE(;
    prefix = joinpath(dirname(@__DIR__), "recipes"),
    preferences = preferences(),
    bootstrap = get_path(prefix, "msix/bootstrap.ps1"),
    windowed = preferences["msix"]["bootstrapper_windowed"],
    sfx_stub = get(preferences, "msix2exe_sfx_stub", MSIX2EXEPack.extract_stub()),
    title = "Installer" # Could be set from app_name from preferences
    )
    
    return MSIX2EXE(bootstrap, windowed, sfx_stub, title)
end

function MSIX2EXE(project; preferences = preferences(), kwargs...)

    prefix = [project, joinpath(project, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    spec = MSIX2EXE(; prefix, preferences, kwargs...)

    return spec
end

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
function repack(msix_archive::String, msix2exe::MSIX2EXE, destination::String; force = false)

    if force
        rm(destination; force=true)
    end
    
    MSIX2EXEPack.pack(msix_archive, msix2exe.bootstrap, destination; title = msix2exe.title, console = !msix2exe.windowed)

    return
end


const SNAP_COMMAND_RE = r"^[A-Za-z0-9/. _#:$-]*$"

function is_valid_snap_command(cmd::Cmd)
    s = Base.shell_escape_posixly(cmd)
    occursin(SNAP_COMMAND_RE, s)
end

"""
    Snap([project]; arch, compress, windowed, kwargs...)
 
Create a Snap configuration object for Linux application packaging.
 
When `project` is provided, configuration files are searched in `project`, then `project/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `project/Project.toml`, and packaging defaults (`windowed`, `compress`, etc.) are read
from `project/LocalPreferences.toml`. Without `project`, only the built-in recipes and the active
project's `LocalPreferences.toml` are used.
 
# Arguments
- `project`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/snap/` overrides
 
# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["snap/icon.png", "icon.png"])`: Path to application icon file
- `snap_config = get_path(prefix, "snap/snap.yaml")`: Path to Snap package metadata template
- `command::Cmd`: Command launching the application; defaults to `snap.command` preference. Its executable and escaped arguments are exposed to the templates as `COMMAND`
- `desktop_launcher = get_path(prefix, "snap/main.desktop")`: Path to desktop entry file template for GUI integration
- `configure_hook`: Path to configuration hook script run on `snap set`; resolved from prefix using the bundler predicate; omitted if not found
- `main_launcher`: Path to main launcher script installed into `bin/`; resolved from prefix using the bundler predicate; omitted if not found
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into a `.snap` archive; defaults to `compress` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `project` is provided, pre-populated from `Project.toml` and preferences: `APP_NAME`, `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`, `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, `MODULE_NAME` (Julia-based bundles only), and `WINDOWED`
 
# Examples
```julia
Snap()                                    # default recipes only
Snap(app_dir)                             # project with Project.toml parameters
Snap(app_dir; windowed = false)           # project with keyword overrides
Snap(; prefix = ["custom/", "recipes/"]) # explicit search path
```
"""
struct Snap # by extensions files could have multiple modes that are set via stage command
    icon::String
    snap_config::String
    command::Cmd
    desktop_launcher::String
    configure_hook::Union{String, Nothing} # needs to be enabled when staging
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
              command = Cmd(preferences["snap"]["command"]),
              desktop_launcher = get_path(prefix, "snap/main.desktop"),
              configure_hook = get_path(prefix, hook("snap/configure.sh", predicate); warn = false),
              windowed = preferences["windowed"],
              compress = preferences["compress"],
              arch = Sys.ARCH,
              parameters = Dict("WINDOWED" => windowed, "COMMAND" => Base.shell_escape_posixly(command))
              )

    # Instead of an error one can create a wrapper and then link to it
    if !is_valid_snap_command(command)
        error(raw"command contains illegal characters (legal: '^[A-Za-z0-9/. _#:$-]*$')")
    end

    return Snap(icon, snap_config, command, desktop_launcher, configure_hook, windowed, compress, arch, predicate, parameters)
end

function Snap(project; preferences = get_project_preferences(project), kwargs...)

    prefix = [project, joinpath(project, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    snap = Snap(; prefix, preferences, kwargs...)
    parameters = get_bundle_parameters!(snap.parameters, preferences)

    return snap
end


# TODO: mention that application needs to be notarized by Apple. That can be done outside the build process by stapling already signed DMG archive. 

"""
    DMG([project]; arch, compress, windowed, kwargs...)
 
Create a DMG configuration object for macOS application packaging.
 
When `project` is provided, configuration files are searched in `project`, then `project/meta`,
then the built-in recipes directory. Application parameters (`APP_NAME`, `APP_VERSION`, etc.) are
read from `project/Project.toml`, and packaging defaults (`selfsign`, `compression`, etc.) are
read from `project/LocalPreferences.toml`. Without `project`, only the built-in recipes and the
active project's `LocalPreferences.toml` are used.
 
# Arguments
- `project`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/dmg/` overrides
 
# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"])`: Path to application icon (.icns or .png)
- `info_config = get_path(prefix, "dmg/Info.plist")`: Path to Info.plist template with app metadata
- `command::Cmd`: Command launching the application; defaults to `dmg.command` preference. Its executable and escaped arguments are exposed to the templates as `COMMAND`
- `entitlements = get_path(prefix, "dmg/Entitlements.plist")`: Path to entitlements file for code signing
- `dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"])`: Path to DS_Store file or TOML template for Finder window appearance
- `selfsign`: If `true`, generate a temporary self-signed certificate instead of using `pfx_cert`; defaults to `selfsign` preference
- `pfx_cert = get_path(prefix, "dmg/certificate.pfx")`: Path to code signing certificate
- `shallow_signing`: If `true`, sign only the top-level bundle rather than all nested binaries; defaults to `dmg.shallow_signing` preference
- `hardened_runtime`: If `true`, enable hardened runtime during signing (required for notarization); defaults to `dmg.hardened_runtime` preference
- `sandboxed_runtime`: If `true`, enable the App Sandbox entitlement; defaults to `dmg.sandboxed_runtime` preference
- `main_launcher`: Path to the Julia entry-point script. When set, a native redirect launcher is installed at `Contents/MacOS/<app_name>` and the script itself at `Contents/Libraries/main`; resolved from prefix using the bundler predicate; omitted if not found
- `hfsplus = false`: If `true`, use HFS+ filesystem when building the disk image otherwise uses ISO
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the staging directory into a `.dmg` disk image; defaults to `compress` preference
- `compression`: Compression algorithm for the disk image (`:lzma`, `:bzip2`, `:zlib`, or `:lzfse`); defaults to `dmg.compression` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `project` is provided, pre-populated from `Project.toml` and preferences: `APP_NAME`, `APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`, `BUNDLE_IDENTIFIER`, `PUBLISHER_DISPLAY_NAME`, `MODULE_NAME` (Julia-based bundles only), `WINDOWED`, and `SANDBOXED_RUNTIME`
 
# Examples
```julia
DMG()                                    # default recipes only
DMG(app_dir)                             # project with Project.toml parameters
DMG(app_dir; hardened_runtime = false)   # project with keyword overrides
DMG(; prefix = ["custom/", "recipes/"]) # explicit search path
```
"""
struct DMG
    icon::String
    info_config::String
    command::Cmd
    entitlements::String
    dsstore::String # if it's toml then use it as source for parsing
    selfsign::Bool
    pfx_cert::Union{String, Nothing}
    shallow_signing::Bool
    hardened_runtime::Bool
    sandboxed_runtime::Bool
    main_launcher::Union{String, Nothing}
    #hfsplus::Bool
    backend::DMGPack.ImageBackend
    windowed::Bool
    compress::Bool
    compression::Symbol
    arch::Symbol
    predicate::String
    parameters::Dict{String, Any}
end


function dmg_backend(preferences)

    backend = preferences["dmg"]["backend"]
    if backend == "xorriso"
        return DMGPack.XorrisoBackend(preferences["dmg"]["xorriso"]["hfsplus"])
    elseif backend == "hfsplus"
        return DMGPack.HFSPlusBackend(preferences["dmg"]["hfsplus"]["slack"])
    else
        error("Unrecognized backend $backend. Allowed values xorriso|hfsplus")
    end

end

# soft link can be used in case one needs to use png source. The issue here is of communicating intent.
function DMG(;
             prefix = joinpath(dirname(@__DIR__), "recipes"),
             preferences = preferences(),
             predicate = preferences["bundler"],
             icon = get_path(prefix, ["dmg/icon.icns", "icon.icns"]), # The "dmg/icon.png" is not yet supported
             info_config = get_path(prefix, "dmg/Info.plist"),
             command = Cmd(preferences["dmg"]["command"]),
             entitlements = get_path(prefix, "dmg/Entitlements.plist"),
             dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"]),
             selfsign = preferences["selfsign"],
             pfx_cert = preferences["skipsign"] ? nothing : get_path(prefix, "dmg/certificate.pfx"),
             shallow_signing = preferences["dmg"]["shallow_signing"],
             hardened_runtime = preferences["dmg"]["hardened_runtime"],
             sandboxed_runtime = preferences["dmg"]["sandboxed_runtime"],
             main_launcher = get_path(prefix, hook("dmg/main.sh", predicate); warn = false),
             #hfsplus = false,
             backend = dmg_backend(preferences),
             windowed = preferences["windowed"],
             compress = preferences["compress"],
             compression = preferences["dmg"]["compression"] |> Symbol,
             arch = Sys.ARCH,
             parameters = Dict("WINDOWED" => windowed, "SANDBOXED_RUNTIME" => string(sandboxed_runtime), "COMMAND"=>Base.shell_escape_posixly(command))
             )

#    return DMG(icon, info_config, command, entitlements, dsstore, selfsign, pfx_cert, shallow_signing, hardened_runtime, sandboxed_runtime, main_launcher, hfsplus, windowed, compress, compression, arch, predicate, parameters)
    return DMG(icon, info_config, command, entitlements, dsstore, selfsign, pfx_cert, shallow_signing, hardened_runtime, sandboxed_runtime, main_launcher, backend, windowed, compress, compression, arch, predicate, parameters)
end

function DMG(project; preferences = get_project_preferences(project), kwargs...)

    prefix = [project, joinpath(project, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    dmg = DMG(; prefix, preferences, kwargs...)
    get_bundle_parameters!(dmg.parameters, preferences)
    
    return dmg
end


"""
    stage(config, destination::String; [dsstore=false])
 
Stage package metadata and directory structure into `destination` in preparation for bundling.
 
`config` is a format-specific configuration object — [`MSIX`](@ref), [`DMG`](@ref), or
[`Snap`](@ref) — that carries the template files, parameters, and settings for the target
platform. Mustache-rendered templates are written using the parameters stored in `config`.
 
`stage` is called automatically by [`bundle`](@ref), but can be used directly when you need
to inspect or modify the staging directory before compression and signing.
 
## Staged layout by format
 
**MSIX**
- `Assets/` — application icons (generated from source or copied verbatim if already a directory)
- `AppxManifest.xml` — rendered package manifest
- `resources.pri` — package resource index
- `Msix.AppInstaller.Data/MSIXAppInstallerData.xml` — rendered installer configuration
 
**DMG**
- `Contents/Resources/icon.icns` — application icon
- `Contents/Info.plist` — rendered application metadata
- `Contents/MacOS/<app-name>` (optional) — native launcher when `main_launcher` is set
 
  When `dsstore = true`, also writes into the *parent* of `destination`:
  - `Applications` — symlink to `/Applications` for drag-and-drop installation
  - `.DS_Store` — custom Finder window appearance
 
**Snap**
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
    app_exe = parameters["APP_EXE"]

    install(dmg.icon, joinpath(destination, "Contents/Resources/icon.icns"))
    install(dmg.info_config, joinpath(destination, "Contents/Info.plist"); parameters, predicate)

    if dsstore
        symlink("/Applications", joinpath(dirname(destination), "Applications"); dir_target=true)
        install_dsstore(dmg.dsstore, joinpath(dirname(destination), ".DS_Store"); parameters)
    end

    if !isnothing(dmg.main_launcher)
        launcher = retrieve_macos_launcher(MacOS(dmg.arch))
        install(launcher, joinpath(destination, "Contents/MacOS/$app_exe"); executable = true)

        install(dmg.main_launcher, joinpath(destination, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true, predicate = dmg.predicate)
    end

    return
end

function stage(snap::Snap, destination::String)

    (; predicate, parameters) = snap
    app_exe = parameters["APP_EXE"]

    install(snap.icon, joinpath(destination, "meta/icon.png"))
    install(snap.snap_config, joinpath(destination, "meta/snap.yaml"); parameters, predicate)
    install(snap.desktop_launcher, joinpath(destination, "meta/gui/$app_exe.desktop"); parameters, predicate)
    
    if !isnothing(snap.configure_hook)
        install(snap.configure_hook, joinpath(destination, "meta/hooks/configure"); parameters, executable = true, predicate)
    end

    return
end


"""
    bundle(setup::Function, config, destination::String; force=false, [password=""])
 
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
    
    #DMGPack.pack(app_stage, destination, entitlements; pfx_path, password, compression = dmg.compress ? dmg.compression : nothing, installer_title, shallow_signing = dmg.shallow_signing, hardened_runtime = dmg.hardened_runtime, hfsplus = dmg.hfsplus)

    DMGPack.pack(app_stage, destination, entitlements; pfx_path, password, compression = dmg.compress ? dmg.compression : nothing, installer_title, shallow_signing = dmg.shallow_signing, hardened_runtime = dmg.hardened_runtime, backend = dmg.backend)

    return
end

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


"""
    AppImage([project]; arch, compress, compression, runtime, kwargs...)

Create an AppImage configuration object for Linux application packaging.

AppImage is a single executable file for Linux that is mounted rather than installed. It suits applications made of thousands of small files, which are slow to unpack and hydrate on the network filesystems used by HPC clusters.

Mounting requires `fusermount` on the target machine. Where it is missing the runtime falls back to
`--appimage-extract-and-run`, and [`AppBundler.AppImagePack.unpack`](@ref) reads the payload without
running the runtime at all.

The staged AppDir contains only the `AppRun` entry point and the application payload; no desktop
entry, icon or AppStream metadata is included, so the AppImage does not integrate with desktop menus.

# Arguments
- `project`: Path to a project directory containing `Project.toml`, optional `LocalPreferences.toml`, and optional `meta/appimage/` overrides

# Keyword Arguments
- `prefix = joinpath(dirname(@__DIR__), "recipes")`: Base directory or array of directories to search for configuration files in sequential order
- `apprun`: Path to the `AppRun` template; resolved from prefix using the bundler predicate
- `command::Cmd`: Command launching the application; defaults to `appimage.command` preference. Its executable and escaped arguments are exposed to the templates as `COMMAND`
- `compression`: squashfs compressor, one of `:zstd` (default), `:gzip` or `:xz`; defaults to the
  `appimage.compression` preference
- `runtime`: Path to the AppImage runtime. When unset, `AppImageRuntime_jll` is used if installed;
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference
- `compress`: If `true`, pack the AppDir into an `.AppImage`; defaults to `compress` preference
- `arch = Sys.ARCH`: Target CPU architecture
- `predicate`: Bundler predicate used for hook selection; defaults to `bundler` preference
- `parameters`: Dictionary of parameters for Mustache template rendering. When `project` is provided, pre-populated from `Project.toml` and preferences

# Examples
```julia
appimage_config = AppImage(app_dir)

bundle(appimage_config, appimage_archive) do app_stage
    # install application into app_stage
end
```
"""
struct AppImage
    apprun::String # It is always AppRun.sh. 
    command::Cmd
    compression::Symbol
    compress::Bool
    arch::Symbol
    runtime::String
    predicate::String
    parameters::Dict{String, Any}
end

function AppImage(;
                  prefix = joinpath(dirname(@__DIR__), "recipes"),
                  preferences = preferences(),
                  predicate = preferences["bundler"],
                  apprun = get_path(prefix, hook("appimage/AppRun.sh", predicate); warn = false),
                  command = Cmd(preferences["appimage"]["command"]),
                  compression = Symbol(get(preferences["appimage"], "compression", "zstd")),
                  windowed = preferences["windowed"],
                  compress = preferences["compress"],
                  arch = Sys.ARCH,
                  runtime = AppImageRuntime.get_runtime(arch),
                  parameters = Dict{String, Any}("WINDOWED" => windowed, "COMMAND" => Base.shell_escape_posixly(command))
                  )

    compression in AppImagePack.COMPRESSORS ||
        error("`appimage_compression` must be one of: " *
              join(AppImagePack.COMPRESSORS, ", ") * ". Got `$compression`.")

    return AppImage(apprun, command, compression, compress, arch, runtime, predicate, parameters)
end

function AppImage(project; preferences = get_project_preferences(project), kwargs...)

    prefix = [project, joinpath(project, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    appimage = AppImage(; prefix, preferences, kwargs...)
    get_bundle_parameters!(appimage.parameters, preferences)

    return appimage
end

function stage(appimage::AppImage, destination::String)

    (; predicate, parameters) = appimage

    install(appimage.apprun, joinpath(destination, "AppRun"); parameters, executable = true, predicate)

    return
end

function bundle(setup::Function, appimage::AppImage, destination::String; force = false)

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    appdir = appimage.compress ? mktempdir() : destination

    @info "Initializing AppDir staging layout..."
    stage(appimage, appdir)

    @info "Installing app into staging area..."
    setup(appdir)

    if appimage.compress
        @info "Packaging AppDir into AppImage..."
        AppImagePack.pack(appdir, destination; compression = appimage.compression, runtime = appimage.runtime)
    end

    return
end
