# Customization

Every operating system is different and has made unique design choices. On macOS, applications are simply put within the Applications folder from DMG containers. Windows uses many formats, with MSIX being the most modern approach, and Linux uses Snap and Flatpak for external software distribution. To create an installer on each of these platforms, there is a list of common tasks that one needs to perform individually:

- Make icon assets in a form that the installer/operating system understands
- Specify the needed capabilities for the application
- Set the launching endpoint, whether it is a GUI or a terminal application
- Bundle all configuration files with the application into the installer
- Perform code signing of the installer and possibly the application

Maintaining all these configuration nuances is hard. AppBundler resolves these issues with defaults that enable shipping GUI applications effortlessly while also enabling developers to simply configure the installer with their own configuration overlay in places where they need it, making the process much easier to debug and communicate about.

## Command line parameters

The main customization for what happens onece user runs `appbundler build . --build-dir=build` happens though `LocalPreferences.toml` file few passed commmand line arguments like `--target-arch` determining the target arhitecure for which the bundle is created, `--target-bundle` which is `msix|snap|dmg`. `--target-name` enables to set a custom name of the darget which by default is `{{app_name}}-{{version}}-{{arch}}`. The command line arguments also offer `--selfsign` flag for self signing of the resulting bundle and `--password` that is a password for certificate file which is used for signing. A `--debug` build creates an uncompressed bundle with console window that is selfsigned enabling quick debugging workflow. `--force` flag overwrites the destination if present. In addition `-D` options is supported to override default parameters read from `LocalPreferences.toml`. 

```@example
using AppBundler # hide
AppBundler.print_help() # hide
```

## Preferences

The main parameters are read from `LocalPreferences.toml` and in addition from `Project.toml` reading the module name and application version from there (`LocalPreferences` can be used to override thoose parameters). The full list of available parameters can be seen within `joinpath(pkgdir(AppBundler), "LocalPreferences.toml")`. To use the preferences it is important to add in the application `Project.toml`:
```
[extras]
AppBundler = "40eb83ae-c93a-480c-8f39-f018b568f472"
```
as otherwise the preferences for `AppBundler` are not registered. A typical `LocalPreferences.toml` is generally short like:
```
[AppBundler]
windowed = false
bundler = "juliac"
juliac_trim = true
```
A generic metedata infomation of the bundle (Theese are all the parameters which does not affect runtime behaviour of the bundle):
- `app_name` application name (by default taken as package version from `Project.toml`)
- `version` application version (by default taken as package name from `Project.toml`)
- `app_summary` summary of the application which is placed in releavnt contexts for MSIX and Snap installers.
- `app_description` a longer description of the application used for Snap installer.
- `publisher_name` name of the publisher
- `bundle_identifier` publisher identifier for DMG in the for of (by default `org.appbundler.{{app_name}}`)
- `build_number` is by default set as commit count of application git repostiory and uses 0 if that fails.

The next set of the parameters is a common set of parameters applied accroos the bundles:
- `windowed` determines whether application diesplays a console at the runtime. 
- `compress` whether resulting application shall be compressed in the bundle or left as directory
- `selfsign` whether resulting aplication shall be signed with self signed certificate
- `overwrite_target` whetehr the resulting bundle shall overwrite already present bundle.

The next set of parameters configures the MSIX and DMG bundles. We have parameters:
- `msix_path_length_threshold` configures the maximum allowed length within the bundle. This is important when one uses AppBundler on windows as bundling long paths is not supported.
- `msix_skip_long_paths` if long paths are present whether to error the bundiling or skip them
- `msix_skip_symlinks` whether to skip symlinks. (default true)
- `msix_skip_unicode_paths` whether to skip unicode paths or let the bundle to error (default true)
- `msix_publisher` this is a publisher string that one can specify manually that is used as metadata for self signing certifcate generation which is included in `AppxManifest.xml`. Because the publisher needs to match exactly with the certificate it is read from the certificate at the bundling time and inlined into `AppxManifest.xml` automatically (default "CN=AppBundler, C=XX, O=PeaceFounder"). 

Fof DMGs we have:
- `dmg_shallow_signing` whether to sign only the topmost binary. This must be disabled in deployment when one is willing to notarize their application with apple (default true)
- `dmg_hardened_runtime` whether hardened runtime is enabled during the signing. (default true)
- `dmg_sandboxed_runtime` sandboxed runtime that limits access to peripheries, system directories and etc (default false).
- `dmg_compression` compression algorithm that is used for compressing the DMG bundle available `bzip2|zlib|lzma|lzfse` (default `lzma`)

The next set of preferences concerns the bundling of the source code into self contained applications. 
- `bundler` selects the bundler which will bundle the source code availabel options `juliaimg|juliac` (default `juliaimg`)
- `juliaimg_mainless` whether launcher shall launch `bin/julia` directly without calling main function of the packaged application. This option is used for making Julia distributions where (default `false`)
- `juliaimg_precompile` option allows to choose whether perform application precompilation of the project modules or deffer that to the client when it first initializes the code (default `true`)
- `juliaimg_incremental` whether precompilation cache from Julia itself is removed or added on top of it which makes compilation quicker. (default `false`)
- `juliaimg_sysimg` a list of packages that shall be baked into system image. Note that only top package needs to be specified as dependencies are baked in automatically (default `[]`)
- `juliaimg_selective_assets` whether enable selective assets. See AppEnv for details. This option works only when modules are baked into sysimg as it removes all sources (default `false`)
- `juliac_trim` whether enable trimming when compiling with `juliac`. (default `false`)

## AppEnv

AppEnv is essential ingridient for starting Julia application and is the first module that is imported in for juliaimg bundles. At runtime it sets up `LOAD_PATH`, `DEPOT_PATH` so that application uses it's compiled precompilation cache proerly. For `Snap` applications the precompilation cache can be gneratd during installation via `configure` hook, which is also included here. AppEnv also sets up `AppEnv.USER_DATA` directory where applications can store theri settings. 

Once applications are launched they define a `USER_DATA` environment variable where apps can store their data. On Linux and Windows, those are designated application locations which get removed with the uninstallation of the app, whereas on macOS, apps use `~/.config/myapp` and `~/.cache/myapp` folders unless run from a sandbox, in which case the `$HOME/Library/Application Support/Local` folder will be used.

AppEnv also offers asset managment by initializing `pkgorigins` from an index created during compilation step. This enables to place assets within the package directories and reference them via `pkgdir(@__MODULE__)` in a relocatable way while only including selected list of assets. When JuliaC is used it is expected that one structures the main application as:

```
using AppEnv

function (@main)(ARGS)
    AppEnv.init()
    # Do the rest; Optionally also reffer to user data directory via AppEnv.USER_DATA
end
```
which loads pkgorigins from a stored index within compiled application so the runtime can locate the assets. Note that `AppEnv.init()` does compile with JuliaC with triming enabled and is added part of the tests. 

Selective assets for `juliaimg` are optional can be enabled via `juliaimg_selective_assets` which removes all source code whereas with `juliac` bundler selective assets are the only option.

Selective assets are listed for each module and coresponding dependecy within Preferences via `assets` variabnle in `LocalPreferences.toml`:
```
[AppEnv]
assets = ["LICENSE"]

[QMLApp]
assets = ["src/App.qml"]

[AppBundler]
# AppBundler options
```
which includes all source code files and etc. Such syntax also enables package developers to list their runtime assets while the users to oevrride them in noninvasive way. In this case the assets would be stored in the main directory in `assets/AppEnv` and `assets/QMLApp`.

## Surgical Overrides

The Appbundler is designed with surgical customization via native file overrides in mind. The files placed in the application `meta` directory are overriding files that are listed in `joinpath(pkgdir(AppBundler), "recipes")`. Common customization scenarios include sandboxing configuration (adding specific capabilities or interfaces your application needs), custom launchers (defining alternative entry points), and icon overrides (providing platform-specific icon assets in various sizes). By keeping templates simple and encouraging users to copy and modify complete configuration files rather than creating complex nested templates, AppBundler makes platform-specific customization straightforward and debuggable.

To get a glimpse on how it works consider a common situation where you would like to use a custom icon for you application. To do so you need to provide `icon.png` and `icon.icns` and place that within `meta` directory of you application. During application bundling AppBundler looks first whether an icon `meta/icon.png` or `meta/icon.icns` exists within the built application. If so it uses thoose as the paths. However, if they don't exist it reverst to defaults which are `joinpath(pkgdir(AppBundler), "recipes/icon.png")` and `joinpath(pkgdir(AppBundler), "recipes/icon.icns")` respecitvelly. 

If we look in the configuration files like for instance `recipes/snap/main.desktop` we see that
```
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
the configuration file iteldf is a template of the parameters which get inlined at the bundling stage. As a general rule the available variables are capitalized versions of what is specified with preferences. In this example for instance we also see how the conditional logic on whether showing a terminal is implemented via `{{#WINDOWED}}false{{/WINDOWED}}{{^WINDOWED}}true{{/WINDOWED}}` which is controlled with `windowed` preference in `LocalPreferences.toml`. When overriding one may or may not keep the variables and can set the poarameters directly in the configuration files. 

Some of the configuration files are specific to the bundler. For instance `juliaimg` bundler requires a special `main` launcher wheras `juliac` bundler can point to the resulting application directly. This is exampliifided with `recipes/snap/juliaimg_main.sh`:
```
#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/julia"
$JULIA {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}} $@
```
which gets picked up in the bundling only for `juliaimg` bundling. In the configuration files `juliaimg` is the predicate. Furthermore to override it one may either provide `meta/snap/juliaimg_main.sh` or `meta/snap/main.sh` (but at the cost that it would also be picked up for `juliac` bundler). 

Some of the configuration files are not installed directly in the bundle but are essential ingirdients. Such ones are `recipes/dmg/Entitlements.plsit` which are insputs in the codesigning that determies varios snadboxing permissions and `recipes/dmg/DS_Store.toml` that sepcifies `.DS_Store` file as a TOML file of user editing wheras only compiled `.DS_Store` is instaled in the DMG. 

The sandboxing of the application is controlled (such as accessing hardware, networking capabilities, or custom launchers), you can override defaults by placing custom configuration files in your `meta` folder: `meta/snap/snap.yaml` for Linux, `meta/msix/AppxManifest.xml` for Windows, or `meta/dmg/Entitlements.plist` for macOS. Figuring which configurations work and which does not work is up to the user. AppBundler offer `--debug` flag which enables [quicker troubleshooting](troubleshooting.md).





