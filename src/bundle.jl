import Mustache
import IconTools
import DmgPack
import MsixPack

"""
    AppInfo([preferences::Dict]; kwargs...)

Application metadata shared by all bundle configurations. Each field defaults to the matching key
in `preferences` (the `AppBundler` preferences section), falling back to the values listed below.
The format constructors [`MSIX`](@ref), [`DMG`](@ref), [`Snap`](@ref) and [`AppImage`](@ref)
forward their remaining keyword arguments here.

# Keyword Arguments
- `predicate`: Bundler predicate; defaults to `bundler` preference, or `nothing`
- `arch = Sys.ARCH`: Target CPU architecture
- `windowed`: If `true`, the application runs without a console window; defaults to `windowed` preference, or `false`
- `app_name`: defaults to `app_name` preference, or `"MyApp"`
- `app_exe`: defaults to `app_exe` preference, or `lowercase(app_name)`
- `app_display_name`: defaults to `app_display_name` preference, or `app_name`
- `app_version`: defaults to `app_version` preference, or `"0.0.1"`
- `build_number`: defaults to `build_number` preference, or `0`
- `app_summary`, `app_description`: Short and long application descriptions
- `bundle_identifier`: defaults to `bundle_identifier` preference, or `"org.appbundler.<app_exe>"`
- `publisher_name`: defaults to `publisher_name` preference, or `"AppBundler"`

`parameters(appinfo)` exposes these to Mustache templates as `WINDOWED`, `APP_NAME`, `APP_EXE`,
`APP_DISPLAY_NAME`, `APP_VERSION`, `BUILD_NUMBER`, `APP_SUMMARY`, `APP_DESCRIPTION`,
`BUNDLE_IDENTIFIER` and `PUBLISHER_DISPLAY_NAME`, plus the upper-cased predicate set to `true`.
"""
struct AppInfo
    predicate::Union{String, Nothing} 
    arch::Symbol 
    windowed::Bool
    app_name::String
    app_exe::String 
    app_display_name::String 
    app_version::String
    build_number::Int
    app_summary::String
    app_description::String 
    bundle_identifier::String 
    publisher_name::String 
end

function AppInfo(preferences::Dict; 
                 predicate = get(preferences, "bundler", nothing),
                 arch = Sys.ARCH,
                 windowed =  get(preferences, "windowed", false),
                 app_name = get(preferences, "app_name", "MyApp"),
                 app_exe = get(preferences, "app_exe", lowercase(app_name)),
                 app_display_name = get(preferences, "app_display_name", app_name),
                 app_version = get(preferences, "version", "0.0.1"),
                 build_number = get(preferences, "build_number", 0),
                 app_summary = get(preferences, "app_summary", "APP_SUMMARY TEXT"),
                 app_description = get(preferences, "app_description", "APP_DESCRIPTION TEXT"),
                 bundle_identifier = get(preferences, "bundle_identifier", "org.appbundler.$app_exe"),
                 publisher_name = get(preferences, "publisher_name", "AppBundler"),
                 )

    return AppInfo(predicate, arch, windowed, app_name, app_exe, app_display_name, app_version, build_number, app_summary, app_description, bundle_identifier, publisher_name)
end

AppInfo(; kwargs...) = AppInfo(Dict(); kwargs...)

function parameters(appinfo::AppInfo)

    _parameters = Dict{String, Union{String, Bool, Int}}()

    if !isnothing(appinfo.predicate)
        _parameters[uppercase(appinfo.predicate)] = true
    end

    _parameters["WINDOWED"] = appinfo.windowed

    # This one looks like a bug nest; need to refactor and test
    _parameters["APP_NAME"] = appinfo.app_name
    _parameters["APP_EXE"] = appinfo.app_exe
    _parameters["APP_DISPLAY_NAME"] = appinfo.app_display_name
    _parameters["APP_VERSION"] = appinfo.app_version
    _parameters["BUILD_NUMBER"] = appinfo.build_number
    _parameters["APP_SUMMARY"] = appinfo.app_summary
    _parameters["APP_DESCRIPTION"] = appinfo.app_description
    _parameters["BUNDLE_IDENTIFIER"] = appinfo.bundle_identifier
    _parameters["PUBLISHER_DISPLAY_NAME"] = appinfo.publisher_name

    return _parameters
end

function render_template(source, parameters)
    template = Mustache.load(source)
    return Mustache.render(template, parameters)
end

function project_preferences(project)
    return load_preferences(project)["AppBundler"]    
end

project_preferences(::Nothing) = preferences()


"An .svg/.png that a target-specific icon is generated from."
struct IconSource
    path::String
end

"TOML description that a binary .DS_Store is generated from."
struct DSStoreTOML
    path::String
end


function materialize(source::String, destination)
    mkpath(dirname(destination))
    cp(source, destination)
    return
end

function materialize(source::IconSource, destination)
    mkpath(dirname(destination))

    img = IconTools.load(source.path)
    icon_img = IconTools.toicon(img, 512)
    IconTools.save(destination, icon_img)

    return
end


"""
    bundle(setup::Function, config, destination::String; compress = true, force = false, parameters = parameters(config), [signer = nothing, verbose = false])

Stage, populate, and optionally compress an application bundle for distribution.

`config` is a format-specific configuration object — [`MSIX`](@ref) (Windows), [`DMG`](@ref)
(macOS), [`Snap`](@ref) (Linux), or [`AppImage`](@ref) (Linux) — and `destination` is the path
of the final artifact (e.g. `"MyApp.msix"`, `"MyApp.dmg"`, `"MyApp.snap"`, `"MyApp.AppImage"`)
or, with `compress = false`, of the uncompressed staging directory.

The function follows three steps:

1. **Stage** — renders the configuration's templates with `parameters` and writes platform
   metadata and directory structure into a staging area via [`stage`](@ref). The staging area is
   a temporary directory when `compress = true` and `destination` itself otherwise. For DMG the
   staging area is the `.app` bundle directory.
2. **Setup** — calls `setup(staging_dir)`, where you copy or compile the application
   files that should be included in the bundle.
3. **Pack** — when `compress = true`, compresses the staging area into the final artifact.

If `destination` already exists an error is thrown, unless `force = true`, in which case it is
removed first.

# Keyword Arguments
- `compress = true`: Pack the staging area into `destination`; otherwise leave `destination` as an uncompressed staging directory
- `force = false`: Remove an existing `destination` instead of throwing an error
- `parameters = parameters(config)`: Mustache template parameters
- `signer = nothing`: MSIX and DMG only. Code signing identity; the bundle is left unsigned when `nothing`
- `verbose = false`: MSIX, DMG and Snap only. Verbose output while packing the DMG

## Format-specific behavior

- **MSIX** — after setup, the staging area is checked for Windows compatibility (path length,
  symlinks, non-ASCII paths) according to the `skip_*` settings in the configuration. The package
  is signed after packing, so it is signed only when `compress = true`; the signer's `publisher`
  then replaces `config.publisher` when packing.
- **DMG** — when compressed, the app is staged as `<APP_NAME>.app` together with the Finder
  layout (`.DS_Store` and an `Applications` link), and `"<APP_DISPLAY_NAME> Installer"` is used as
  the volume title, which must not exceed 32 characters. When uncompressed, `destination` is the
  `.app` directory itself, without the Finder layout. AppleDouble `._*` files are removed from the
  staging area before signing. The bundle is signed with the rendered entitlements whenever a
  `signer` is given, also when left uncompressed.
- **Snap** — not signed locally; packages are verified by the Snap Store after upload.
- **AppImage** — not signed.

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

bundle(AppImage(app_dir), "MyApp.AppImage") do staging_dir
    # copy or compile application files into staging_dir
end
```
"""
function bundle end


"""
    MSIX([project]; kwargs...)

Create an MSIX configuration object for Windows application packaging.

Templates and assets are resolved from `project/meta/msix/`, falling back to the built-in recipes.
Defaults are read from the `AppBundler` section of the project's preferences, or of the active
project's preferences when `project` is omitted.

# Arguments
- `project`: Path to a project directory with optional `meta/msix/` overrides

# Keyword Arguments
- `preferences = project_preferences(project)`: Preferences dictionary used for the defaults below
- `icon`: Path to a ready-made `Assets` directory, copied as is, or an [`IconSource`](@ref) from which the MSIX asset set is generated; resolved from `meta/msix/Assets`
- `store_icon_plate`: Background plate color for generated store icons; defaults to `msix.store_icon_plate` preference
- `appxmanifest`: Path to the `AppxManifest.xml` template; resolved from `meta/msix/AppxManifest.xml`
- `command::Cmd`: Command launching the application; defaults to `msix.command` preference
- `resources_pri`: Path to the package resource index, copied as is (generation is not supported); resolved from `meta/msix/resources.pri`
- `msixinstallerdata`: Path to the installer configuration template; resolved from `meta/msix/MSIXAppInstallerData.xml`
- `path_length_threshold`: Maximum allowed path length; defaults to `msix.path_length_threshold` preference
- `skip_long_paths`: If `true`, skip files exceeding path length threshold; if `false`, throw an error; defaults to `msix.skip_long_paths` preference
- `skip_symlinks`: If `true`, skip file and directory symlinks; defaults to `msix.skip_symlinks` preference
- `skip_unicode_paths`: If `true`, skip files with non-ASCII paths; defaults to `msix.skip_unicode_paths` preference
- `publisher`: Publisher string embedded in the manifest (e.g. `"CN=Example, O=Example Ltd"`); defaults to `msix.publisher` preference
- `pfx_cert`: Path to a code signing certificate, or `nothing`; resolved from `meta/msix/certificate.pfx`

Remaining keywords (`predicate`, `arch`, `windowed`, `app_name`, …) are forwarded to [`AppInfo`](@ref).

Templates are rendered with the [`AppInfo`](@ref) parameters plus `PUBLISHER`, `COMMAND_EXE`
(the command's executable) and `COMMAND_ARGS` (its XML-escaped arguments).

# Examples
```julia
MSIX()                                    # active project preferences, built-in recipes
MSIX(app_dir)                             # project with meta/msix overrides
MSIX(app_dir; skip_long_paths = true)     # project with keyword overrides
MSIX(app_dir; command = `bin\\myapp.exe --flag "a b"`)  # custom launch command
MSIX(app_dir; icon = IconSource("icon.svg"))            # generate assets from an icon
```
"""
struct MSIX
    appinfo::AppInfo
    icon::Union{String, IconSource} # direcotry reading is something to look into here
    store_icon_plate::String
    appxmanifest::String 
    command::Cmd
    msixinstallerdata::String 
    resources_pri::String # no genration supported
    path_length_threshold::Int 
    skip_long_paths::Bool 
    skip_symlinks::Bool
    skip_unicode_paths::Bool
    publisher::String
    pfx_cert::Union{String, Nothing} 
end

function MSIX(project = nothing;
              preferences = project_preferences(project),
              icon = resolve(project, "meta/msix/Assets"),
              store_icon_plate = ArgTools.coerce(ColorString(), preferences["msix"]["store_icon_plate"]), 
              appxmanifest = resolve(project, "meta/msix/AppxManifest.xml"),
              command = Cmd(preferences["msix"]["command"]),
              resources_pri = resolve(project, "meta/msix/resources.pri"),
              msixinstallerdata = resolve(project, "meta/msix/MSIXAppInstallerData.xml"),
              path_length_threshold = preferences["msix"]["path_length_threshold"],
              skip_long_paths = preferences["msix"]["skip_long_paths"],
              skip_symlinks = preferences["msix"]["skip_symlinks"],
              skip_unicode_paths = preferences["msix"]["skip_unicode_paths"],
              publisher = preferences["msix"]["publisher"],
              pfx_cert = resolve(project, "meta/msix/certificate.pfx"),
              kwargs...
              )
    
    appinfo = AppInfo(preferences; kwargs...)

    return MSIX(appinfo, icon, store_icon_plate, appxmanifest, command, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths, publisher, pfx_cert)
end

function parameters(msix::MSIX)
    
    _parameters = parameters(msix.appinfo)
    
    _parameters["COMMAND_EXE"] = first(msix.command)
    _parameters["COMMAND_ARGS"] = MsixPack.xml_escape_args(msix.command)
    _parameters["PUBLISHER"] = msix.publisher
    
    return _parameters
end


function stage_layout(msix::MSIX; parameters = parameters(msix))

    manifest = render_template(msix.appxmanifest, parameters)
    assets = msix.icon isa IconSource ? MsixPack.IconSource(msix.icon.path, msix.store_icon_plate) : msix.icon
    resources_pri = msix.resources_pri
    installer_data = render_template(msix.msixinstallerdata, parameters)

    return MsixPack.MSIXLayout(
        manifest, assets, resources_pri, installer_data
    )
end


function stage(msix, destination; kwargs...)

    layout = stage_layout(msix; kwargs...)
    MsixPack.stage(layout, destination)

    return
end


function bundle(setup::Function, msix::MSIX, destination::String; compress = true, signer = nothing, force = false, verbose = false, parameters = parameters(msix))

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end
    app_stage = compress ? mktempdir() : destination

    @info "Initializing MSIX staging layout..."
    stage(msix, app_stage; parameters)
    @info "Installing app into staging area..."
    #setup(app_stage)

    (; path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths) = msix
    MsixPack.ensure_windows_compatability(app_stage; path_length_threshold, skip_long_paths, skip_symlinks, skip_unicode_paths)
    
    if compress
        publisher = isnothing(signer) ? msix.publisher : signer.publisher
        MsixPack.pack(app_stage, destination; publisher)
        if !isnothing(signer)
            MsixPack.sign(destination, signer)
        end
    end

    return
end


const SNAP_COMMAND_RE = r"^[A-Za-z0-9/. _#:$-]*$"

function is_valid_snap_command(cmd::Cmd)
    s = Base.shell_escape_posixly(cmd)
    occursin(SNAP_COMMAND_RE, s)
end


"""
    Snap([project]; kwargs...)

Create a Snap configuration object for Linux application packaging.

Templates and assets are resolved from `project/meta/snap/`, falling back to the built-in recipes.
Defaults are read from the `AppBundler` section of the project's preferences, or of the active
project's preferences when `project` is omitted.

# Arguments
- `project`: Path to a project directory with optional `meta/snap/` overrides

# Keyword Arguments
- `preferences = project_preferences(project)`: Preferences dictionary used for the defaults below
- `predicate`: Bundler predicate used to select the configure hook, also forwarded to [`AppInfo`](@ref); defaults to `bundler` preference
- `icon`: Path to a ready-made PNG icon, copied as is, or an [`IconSource`](@ref) from which it is generated; resolved from `meta/snap/icon.png`
- `snap_config`: Path to the `snap.yaml` metadata template; resolved from `meta/snap/snap.yaml`
- `command::Cmd`: Command launching the application; defaults to `snap.command` preference. An error is thrown if its POSIX-escaped form contains characters outside `[A-Za-z0-9/. _#:\$-]`
- `desktop_launcher`: Path to the desktop entry template; resolved from `meta/snap/main.desktop`
- `configure_hook`: Path to the configuration hook template run on `snap set`; resolved from `meta/snap/configure.sh` using `predicate`, `nothing` if not found

Remaining keywords (`arch`, `windowed`, `app_name`, …) are forwarded to [`AppInfo`](@ref).

Templates are rendered with the [`AppInfo`](@ref) parameters plus `COMMAND`, the POSIX-escaped command.

# Examples
```julia
Snap()                                    # active project preferences, built-in recipes
Snap(app_dir)                             # project with meta/snap overrides
Snap(app_dir; windowed = false)           # project with keyword overrides
```
"""
struct Snap # by extensions files could have multiple modes that are set via stage command
    appinfo::AppInfo
    icon::Union{String, IconSource}
    snap_config::String
    command::Cmd
    desktop_launcher::String
    configure_hook::Union{String, Nothing} # needs to be enabled when staging
end

function Snap(project = nothing;
              preferences = project_preferences(project),
              predicate = get(preferences, "bundler", nothing),
              icon = resolve(project, "meta/snap/icon.png"),
              snap_config = resolve(project, "meta/snap/snap.yaml"),
              command = Cmd(preferences["snap"]["command"]),
              desktop_launcher = resolve(project, "meta/snap/main.desktop"),
              configure_hook = resolve(project, "meta/snap/configure.sh"; predicate),
              kwargs...
              )

    # Instead of an error one can create a wrapper and then link to it
    if !is_valid_snap_command(command)
        error(raw"command contains illegal characters (legal: '^[A-Za-z0-9/. _#:$-]*$')")
    end

    appinfo = AppInfo(preferences; predicate, kwargs...)

    return Snap(appinfo, icon, snap_config, command, desktop_launcher, configure_hook)
end

function parameters(snap::Snap)

    _parameters = parameters(snap.appinfo)
    _parameters["COMMAND"] = Base.shell_escape_posixly(snap.command)

    return _parameters
end


function stage_layout(snap::Snap; parameters = parameters(snap))

    app_exe = snap.appinfo.app_exe

    snap_config = render_template(snap.snap_config, parameters)
    desktop_launcher = render_template(snap.desktop_launcher, parameters)
    configure_hook = isnothing(snap.configure_hook) ? nothing : render_template(snap.configure_hook, parameters)
    
    icon = snap.icon isa IconSource ? SnapPack.IconSource(snap.icon.path) : snap.icon

    return SnapPack.SnapLayout(app_exe, icon, snap_config, desktop_launcher, configure_hook)
end


function stage(snap::Snap, destination::String; kwargs...)
    layout = stage_layout(snap; kwargs...)
    SnapPack.stage(layout, destination)
end


function bundle(setup::Function, snap::Snap, destination::String; compress = true, force = false, verbose = false, parameters = parameters(snap))

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = compress ? mktempdir() : destination

    @info "Initializing Snap staging layout..."
    stage(snap, app_stage; parameters)    
    @info "Installing app into staging area..."
    setup(app_stage)

    if compress
        @info "Packaging staging area into Snap..."
        SnapPack.pack(app_stage, destination)
    end

    return
end


# TODO: mention that application needs to be notarized by Apple. That can be done outside the build process by stapling already signed DMG archive. 

"""
    DMG([project]; kwargs...)

Create a DMG configuration object for macOS application packaging.

Templates and assets are resolved from `project/meta/dmg/`, falling back to the built-in recipes.
Defaults are read from the `AppBundler` section of the project's preferences, or of the active
project's preferences when `project` is omitted.

# Arguments
- `project`: Path to a project directory with optional `meta/dmg/` overrides

# Keyword Arguments
- `preferences = project_preferences(project)`: Preferences dictionary used for the defaults below
- `icon`: Path to a ready-made `.icns` file, copied as is, or an [`IconSource`](@ref) from which it is generated; resolved from `meta/dmg/icon.icns`
- `info_config`: Path to the `Info.plist` template; resolved from `meta/dmg/Info.plist`
- `command::Cmd`: Command launching the application; defaults to `dmg.command` preference
- `entitlements`: Path to the entitlements template used for code signing; resolved from `meta/dmg/Entitlements.plist`
- `dsstore`: Finder window appearance, used only in the full (compressed) layout. Either a path to a ready-made `.DS_Store`, copied as is, or a [`DSStoreTOML`](@ref) that is rendered as a template and converted into a `.DS_Store`; resolved from `meta/dmg/DS_Store`
- `pfx_cert`: Path to a code signing certificate, or `nothing`; resolved from `meta/dmg/certificate.pfx`
- `shallow_signing`: If `true`, sign only the top-level bundle rather than all nested binaries; defaults to `dmg.shallow_signing` preference
- `hardened_runtime`: If `true`, enable hardened runtime during signing (required for notarization); defaults to `dmg.hardened_runtime` preference
- `sandboxed_runtime`: If `true`, enable the App Sandbox entitlement; defaults to `dmg.sandboxed_runtime` preference
- `main_launcher`: Path to the main launcher script template, rendered into `Contents/Libraries/main`; resolved from `meta/dmg/main.sh`
- `backend = dmg_backend(preferences)`: Disk image backend used to build the `.dmg`. Either `DmgPack.XorrisoBackend` (`dmg.backend = "xorriso"`, with the `dmg.xorriso.hfsplus` setting) or `DmgPack.HFSPlusBackend` (`dmg.backend = "hfsplus"`, with `dmg.hfsplus.free_space` controlling spare space in the image)
- `compression`: Compression algorithm for the disk image (`:lzma`, `:bzip2`, `:zlib`, or `:lzfse`); defaults to `dmg.compression` preference

Remaining keywords (`predicate`, `arch`, `windowed`, `app_name`, …) are forwarded to [`AppInfo`](@ref).

Templates are rendered with the [`AppInfo`](@ref) parameters plus `SANDBOXED_RUNTIME` (`"true"` or
`"false"`) and `COMMAND`, the POSIX-escaped command.

# Examples
```julia
DMG()                                    # active project preferences, built-in recipes
DMG(app_dir)                             # project with meta/dmg overrides
DMG(app_dir; hardened_runtime = false)   # project with keyword overrides
```
"""
struct DMG
    appinfo::AppInfo
    icon::Union{String, IconSource}
    info_config::String
    command::Cmd
    entitlements::String
    dsstore::Union{String, DSStoreTOML} # if it's toml then use it as source for parsing
    pfx_cert::Union{String, Nothing}
    shallow_signing::Bool
    hardened_runtime::Bool
    sandboxed_runtime::Bool
    main_launcher::Union{String, Nothing}
    backend::DmgPack.ImageBackend
    compression::Symbol 
end

function dmg_backend(preferences)

    backend = preferences["dmg"]["backend"]
    if backend == "xorriso"
        return DmgPack.XorrisoBackend(; hfsplus = preferences["dmg"]["xorriso"]["hfsplus"])
    elseif backend == "hfsplus"
        return DmgPack.HFSPlusBackend(; free_space = preferences["dmg"]["hfsplus"]["free_space"])
    else
        error("Unrecognized backend $backend. Allowed values xorriso|hfsplus")
    end

end

# soft link can be used in case one needs to use png source. The issue here is of communicating intent.
function DMG(project = nothing;
             preferences = project_preferences(project),
             icon = resolve(project, "meta/dmg/icon.icns"),
             info_config = resolve(project, "meta/dmg/Info.plist"),
             command = Cmd(preferences["dmg"]["command"]),
             entitlements = resolve(project, "meta/dmg/Entitlements.plist"),
             dsstore = resolve(project, "meta/dmg/DS_Store"),
             pfx_cert = resolve(project, "meta/dmg/certificate.pfx"),
             shallow_signing = preferences["dmg"]["shallow_signing"],
             hardened_runtime = preferences["dmg"]["hardened_runtime"],
             sandboxed_runtime = preferences["dmg"]["sandboxed_runtime"],
             main_launcher = resolve(project, "meta/dmg/main.sh"),
             backend = dmg_backend(preferences),
             compression = preferences["dmg"]["compression"] |> Symbol,
             kwargs...
             )

    appinfo = AppInfo(preferences; kwargs...)

    return DMG(appinfo, icon, info_config, command, entitlements, dsstore, pfx_cert, shallow_signing, hardened_runtime, sandboxed_runtime, main_launcher, backend, compression)
end

function parameters(dmg::DMG)

    _parameters = parameters(dmg.appinfo)

    _parameters["SANDBOXED_RUNTIME"] = string(dmg.sandboxed_runtime)
    _parameters["COMMAND"] = Base.shell_escape_posixly(dmg.command)

    return _parameters
end

function get_bundle_name(dmg::DMG)
    app_name = dmg.appinfo.app_name
    return "$app_name.app"
end

function stage_layout(dmg::DMG; full_layout = false, bundle_name = get_bundle_name(dmg), parameters = parameters(dmg))

    info_plist = render_template(dmg.info_config, parameters)
    icon = dmg.icon isa IconSource ? DmgPack.IconSource(dmg.icon.path) : dmg.icon
    launcher = DmgPack.launcher_stub(dmg.appinfo.arch)
    
    if full_layout
        if dmg.dsstore isa DSStoreTOML
            dsstore_toml = render_template(dmg.dsstore.path, parameters)
            dsstore = TOML.parse(dsstore_toml)
        else
            dsstore = dmg.dsstore
        end
        applications_link = true
    else
        dsstore = nothing
        applications_link = false
    end

    return DmgPack.DMGLayout(bundle_name, info_plist, icon, launcher, dsstore, applications_link)
end

function stage(dmg::DMG, destination; bundle_name = get_bundle_name(dmg), kwargs...)

    layout = stage_layout(dmg; bundle_name, kwargs...)
    DmgPack.stage(layout, destination)

    main_launcher = render_template(dmg.main_launcher, parameters(dmg))
    main_path = joinpath(destination, bundle_name, "Contents/Libraries/main")
    mkpath(dirname(main_path))
    write(main_path, main_launcher)
    chmod(main_path, 0o755)

    return
end


function bundle(setup::Function, dmg::DMG, destination::String; compress = true, force = false, signer = nothing, verbose = false, parameters = parameters(dmg)) 

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    @info "Initializing DMG staging layout..."
    if compress
        app_stage = joinpath(mktempdir(), get_bundle_name(dmg))
        full_layout = true
    else
        app_stage = destination
        full_layout = false
    end
    stage(dmg, dirname(app_stage); full_layout, bundle_name = basename(app_stage), parameters)
    
    @info "Installing app into staging area..."
    setup(app_stage)

    DmgPack.clean_app_stage(app_stage)

    if !isnothing(signer)
        @info "Codesigning app..."
        entitlements = render_template(dmg.entitlements, parameters)
        DmgPack.sign(app_stage, signer; entitlements, dmg.shallow_signing, dmg.hardened_runtime)
    end
        
    if compress
        @info "Packaging staging area into DMG..."
        installer_title = join([dmg.appinfo.app_display_name, "Installer"], " ")
        DmgPack.pack(dirname(app_stage), destination; installer_title, dmg.compression, dmg.backend, verbose)

    end
    
    return
end


"""
    AppImage([project]; kwargs...)

Create an AppImage configuration object for Linux application packaging.

AppImage is a single executable file for Linux that is mounted rather than installed. It suits applications made of thousands of small files, which are slow to unpack and hydrate on the network filesystems used by HPC clusters.

Mounting requires `fusermount` on the target machine. Where it is missing the runtime falls back to
`--appimage-extract-and-run`, and [`AppBundler.AppImagePack.unpack`](@ref) reads the payload without
running the runtime at all.

The staged AppDir contains only the `AppRun` entry point and the application payload; no desktop
entry, icon or AppStream metadata is included, so the AppImage does not integrate with desktop menus.

The `AppRun` template is resolved from `project/meta/appimage/`, falling back to the built-in
recipes. Defaults are read from the `AppBundler` section of the project's preferences, or of the
active project's preferences when `project` is omitted.

# Arguments
- `project`: Path to a project directory with optional `meta/appimage/` overrides

# Keyword Arguments
- `preferences = project_preferences(project)`: Preferences dictionary used for the defaults below
- `apprun`: Path to the `AppRun` template; resolved from `meta/appimage/AppRun.sh`
- `command::Cmd`: Command launching the application; defaults to `appimage.command` preference
- `compression`: squashfs compressor, one of `:zstd`, `:gzip` or `:xz`; defaults to the
  `appimage.compression` preference, or `:zstd` when that is unset

Remaining keywords (`predicate`, `arch`, `app_name`, …) are forwarded to [`AppInfo`](@ref).

Templates are rendered with the [`AppInfo`](@ref) parameters plus `COMMAND`, the POSIX-escaped command.

# Examples
```julia
appimage_config = AppImage(app_dir)

bundle(appimage_config, appimage_archive) do app_stage
    # install application into app_stage
end
```
"""
struct AppImage
    appinfo::AppInfo
    apprun::String # It is always AppRun.sh. 
    command::Cmd
    compression::Symbol
end

function AppImage(project = nothing;
                  preferences = project_preferences(project),
                  apprun = resolve(project, "meta/appimage/AppRun.sh"),
                  command = Cmd(preferences["appimage"]["command"]),
                  compression = Symbol(get(preferences["appimage"], "compression", "zstd")),
                  kwargs...
                  )

    compression in AppImagePack.COMPRESSORS ||
        error("`appimage.compression` must be one of: " *
              join(AppImagePack.COMPRESSORS, ", ") * ". Got `$compression`.")

    appinfo = AppInfo(preferences; kwargs...)

    return AppImage(appinfo, apprun, command, compression)
end


function parameters(appimage::AppImage)

    _parameters = parameters(appimage.appinfo)
    _parameters["COMMAND"] = Base.shell_escape_posixly(appimage.command)

    return _parameters
end

function stage_layout(appimage::AppImage; parameters = parameters(appimage))
    
    apprun = render_template(appimage.apprun, parameters)
    return AppImagePack.AppImageLayout(apprun)
end


function stage(appimage::AppImage, destination::String; kwargs...)

    layout = stage_layout(appimage; kwargs...)
    AppImagePack.stage(layout, destination)

    return
end


function bundle(setup::Function, appimage::AppImage, destination::String; compress = true, force = false, parameters = parameters(appimage))

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    appdir = compress ? mktempdir() : destination

    @info "Initializing AppDir staging layout..."
    stage(appimage, appdir; parameters)

    @info "Installing app into staging area..."
    setup(appdir)

    if compress
        @info "Packaging AppDir into AppImage..."
        AppImagePack.pack(appdir, destination; compression = appimage.compression)
    end

    return
end
