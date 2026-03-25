# Customization

Every operating system has made unique design choices for application distribution. On macOS, applications are placed in the Applications folder via DMG containers. Windows supports many installer formats, with MSIX being the most modern. Linux uses Snap and Flatpak for distributing external software. Creating an installer on each platform involves a common set of tasks:

- Producing icon assets in the format the installer or operating system expects
- Declaring the capabilities required by the application
- Specifying the launch entry point, whether GUI or terminal
- Bundling all configuration files with the application
- Code-signing the installer and, where required, the application itself

Maintaining these platform-specific details is burdensome. AppBundler addresses this with sensible defaults that make shipping GUI applications straightforward. Where customization is needed, developers can apply a configuration overlay, keeping the process easy to debug and reason about.

## How It Works

A build follows this pipeline:

```
Project.toml          ← app name, version
LocalPreferences.toml ← all build parameters
meta/                 ← optional file overrides
        ↓
appbundler build . --build-dir=build
        ↓
build/<name>.{msix,snap,dmg}
```

Most builds require only a short `LocalPreferences.toml`. Build customization is done by placing files in `meta/` that override AppBundler's built-in bundle templates — no changes to the core tool needed.

> **Iterating quickly:** Use `--debug` for faster iteration when troubleshooting packaging or sandboxing issues — see [Surgical Overrides](#surgical-overrides).

## Command-Line Parameters

```@example
using AppBundler # hide
AppBundler.print_help() # hide
```

## Preferences

Parameters are read from `LocalPreferences.toml` and from `Project.toml` (for the module name and application version; `LocalPreferences.toml` can override these). The full list of available parameters is in `joinpath(pkgdir(AppBundler), "LocalPreferences.toml")`.

To enable AppBundler preferences, add the following to your application's `Project.toml`; otherwise the preferences for `AppBundler` will not be registered:

```toml
[extras]
AppBundler = "40eb83ae-c93a-480c-8f39-f018b568f472"
```

A typical `LocalPreferences.toml` is short:

```toml
[AppBundler]
windowed = false
bundler = "juliac"
juliac_trim = true
```

### Quick Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| **Metadata** | | |
| `app_name` | from `Project.toml` | Application name |
| `version` | from `Project.toml` | Application version |
| `app_summary` | — | Short description for MSIX and Snap |
| `app_description` | — | Longer description for Snap |
| `publisher_name` | — | Publisher name |
| `bundle_identifier` | `org.appbundler.{{app_name}}` | Bundle identifier for DMG |
| `build_number` | git commit count | Falls back to `0` if git is unavailable |
| **Common** | | |
| `windowed` | `false` | Hide a console window at runtime |
| `compress` | `true` | Compress the application inside the bundle |
| `selfsign` | `false` | Sign with a self-signed certificate |
| `overwrite_target` | `false` | Overwrite target path (`--force`) |
| **Bundler** | | |
| `bundler` | `juliaimg` | Bundler to use: `juliaimg` or `juliac` |
| `juliaimg_mainless` | `false` | Launch `bin/julia` directly without calling `main` |
| `juliaimg_precompile` | `true` | Precompile project modules |
| `juliaimg_incremental` | `false` | Build cache on top of Julia's own rather than starting fresh |
| `juliaimg_sysimg` | `[]` | Packages to bake into the system image |
| `juliaimg_selective_assets` | `false` | Enable selective asset inclusion (see [AppEnv](#appenv)) |
| `juliac_trim` | `false` | Enable trimming when compiling with `juliac` |
| **MSIX** | | |
| `msix_path_length_threshold` | `260` | Maximum allowed path length within the bundle |
| `msix_skip_long_paths` | `false` | Skip paths exceeding the threshold instead of erroring |
| `msix_skip_symlinks` | `true` | Skip symlinks |
| `msix_skip_unicode_paths` | `true` | Skip Unicode paths instead of erroring |
| `msix_publisher` | `"CN=AppBundler, C=XX, O=PeaceFounder"` | Publisher string for `AppxManifest.xml` |
| **DMG** | | |
| `dmg_shallow_signing` | `true` | Sign only the top-level binary |
| `dmg_hardened_runtime` | `true` | Enable hardened runtime during signing |
| `dmg_sandboxed_runtime` | `false` | Restrict access to peripherals and system directories |
| `dmg_compression` | `lzma` | Compression algorithm: `bzip2`, `zlib`, `lzma`, or `lzfse` |

**Bundler.** The `bundler` choice determines which recipe files are applied and which `juliaimg_*` or `juliac_*` parameters are relevant. `juliaimg_mainless` is intended for Julia distributions that launch `bin/julia` directly rather than calling an application `main`. `juliaimg_sysimg` only needs top-level packages — dependencies are baked in automatically. `juliaimg_selective_assets` requires modules to be in the sysimage, since it removes all source files from the bundle; with the `juliac` bundler, selective assets are always used.

**MSIX.** Windows does not support long paths inside bundles, so `msix_path_length_threshold` and `msix_skip_long_paths` exist to either warn or skip offending paths rather than erroring out. The `msix_publisher` string must match the signing certificate exactly; AppBundler reads it from the certificate at bundle time and inlines it into `AppxManifest.xml` automatically, so manual edits are rarely needed.

**DMG.** `dmg_shallow_signing` must be set to `false` when submitting for Apple notarization, as all binaries must be signed individually. `dmg_sandboxed_runtime` restricts access to peripherals and system directories and should only be enabled if your application is designed to run in a sandbox.

## AppEnv

AppEnv is a small runtime support library that bridges the gap between a bundled Julia application and the host operating system. It handles three concerns that every bundled Julia app needs: environment setup, user data directories, and asset location.

AppEnv is the first module loaded in `juliaimg` bundles. At runtime it configures `LOAD_PATH` and `DEPOT_PATH` so the application uses its compiled precompilation cache correctly. For Snap applications, the precompilation cache can be generated during installation via a `configure` hook, which AppEnv also provides.

### User Data Directory

At launch, AppEnv sets the `AppEnv.USER_DATA` variable to a platform-appropriate writable location where the application can store settings, caches, and other persistent data. On Snap and MSIX the directory is managed by the operating system and is removed automatically when the application is uninstalled. The location can always be overridden by setting the `USER_DATA` environment variable before launch.

- **DMG** — `~/.config/<app_name>` (the depot goes to `~/.cache/<app_name>`)
- **DMG (sandboxed)** — `~/Library/Application Support/Local` (detected via `APP_SANDBOX_CONTAINER_ID`)
- **MSIX** — `%LOCALAPPDATA%\Packages\<bundle_identifier>_<hash>\LocalState`
- **Snap** — `$SNAP_USER_DATA` (set directly from the Snap environment variable)

### Asset Management

AppEnv initializes `pkgorigins` from an index created at compile time. This allows assets to be placed within package directories and referenced via `pkgdir(@__MODULE__)` in a relocatable way, while only including a selected subset of files.

Assets are declared per-module in `LocalPreferences.toml` using the `assets` key:

```toml
[AppEnv]
assets = ["LICENSE"]

[QMLApp]
assets = ["src/App.qml"]

[AppBundler]
# AppBundler options
```

Assets are stored under `assets/AppEnv` and `assets/QMLApp` in the main directory. Package developers can declare their runtime assets here, while application developers can override them non-invasively.

Selective assets are optional with `juliaimg` (enabled via `juliaimg_selective_assets`, which removes all source code from the bundle), but are the only mode available with the `juliac` bundler.

### Application Structure

When using JuliaC, the recommended entry point is:

```julia
using AppEnv

function (@main)(ARGS)
    AppEnv.init()
    # Application logic; optionally reference AppEnv.USER_DATA
end
```

`AppEnv.init()` loads `pkgorigins` from a stored index within the compiled application so the runtime can locate assets and sets up `USER_DATA`. In `juliaimg` bundles it is called implicitly via `etc/julia/startup.jl`, so `USER_DATA` is available without any explicit call. With `juliac`, it must be called explicitly as shown above. In an interactive Julia session it does nothing, so it can be left in place during development without affecting application behaviour. It compiles correctly with JuliaC when trimming is enabled and is covered by the test suite.

## Surgical Overrides

AppBundler is designed for surgical customization through native file overrides. Files placed in the application's `meta/` directory override AppBundler's default templates located at `$(pkgdir(AppBundler))/recipes/`. Templates are kept intentionally simple — rather than providing complex nested templates, AppBundler encourages copying and modifying complete configuration files, which keeps platform-specific customization straightforward to debug and communicate about.

> **Tip:** Use `--debug` when working through override changes. It produces an uncompressed, self-signed bundle quickly and opens a console window so you can observe runtime behaviour without waiting for a full release build.

### Override Locations

| Format | Directory | Files |
|--------|-----------|-------|
| DMG | `meta/dmg/` | `Entitlements.plist`, `Info.plist`, `DS_Store.toml`, `juliac_main.sh`, `juliaimg_main.sh` |
| MSIX | `meta/msix/` | `AppxManifest.xml`, `MSIXAppInstallerData.xml`, `resources.pri` |
| Snap | `meta/snap/` | `snap.yaml`, `main.desktop`, `juliaimg_main.sh`, `juliaimg_configure.sh` |
| All | `meta/` | `icon.png`, `icon.icns`, `startup.jl` (juliaimg only) |

### Icons

To use a custom application icon, place `icon.png` and `icon.icns` in the `meta/` directory. During bundling, AppBundler checks for these files first and falls back to its built-in defaults if they are not present.

### Template Variables

Configuration files are Mustache templates. Variables are inlined at bundle time as capitalized versions of the preference names. For example, `meta/snap/main.desktop`:

```desktop
[Desktop Entry]
Name={{APP_DISPLAY_NAME}}
Exec={{APP_NAME}}
Icon=${SNAP}/meta/icon.png
Version={{APP_VERSION}}
Comment={{APP_SUMMARY}}
Terminal={{#WINDOWED}}false{{/WINDOWED}}{{^WINDOWED}}true{{/WINDOWED}}
Type=Application
Categories=Utility;
```

The `{{#WINDOWED}}...{{/WINDOWED}}` / `{{^WINDOWED}}...{{/WINDOWED}}` pattern implements conditional logic driven by the `windowed` preference. When overriding a template, variables may be kept or replaced with static values.

Some files are not installed directly into the bundle but are used as inputs during the build. `meta/dmg/Entitlements.plist` configures the sandbox baked into the signature of the main launcher, and `meta/dmg/DS_Store.toml` is a user-editable TOML representation of `.DS_Store` that is compiled into a binary `.DS_Store` before being placed in the DMG.

### Bundler-Specific Files

Some files only apply to a specific bundler, indicated by a `juliac_` or `juliaimg_` prefix. For instance, `meta/snap/juliaimg_main.sh` is picked up only when using `juliaimg`:

```bash
#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/julia"
$JULIA {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}} $@
```

The equivalent for `juliac` is `meta/snap/juliac_main.sh` (and `meta/dmg/juliac_main.sh` on macOS), which can point directly to the compiled binary. To override a launcher, place a replacement at the prefixed path (e.g. `meta/snap/juliaimg_main.sh`) to target only that bundler, or at the unprefixed path (e.g. `meta/snap/main.sh`) to apply to both. `meta/startup.jl` is specific to `juliaimg` bundles — it is placed in `etc/julia/` inside the bundle and is responsible for calling `AppEnv.init()` implicitly.

### Sandboxing and Capabilities

To customize sandboxing — such as granting access to hardware, networking, or custom launchers — override the relevant configuration file in your `meta/` folder: `Entitlements.plist` for DMG, `AppxManifest.xml` for MSIX, and `snap.yaml` for Snap. Use `--debug` to iterate quickly when working through capability changes, and refer to the [troubleshooting guide](troubleshooting.md) if the application does not behave as expected.
