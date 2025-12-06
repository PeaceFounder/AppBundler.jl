# AppBundler.jl
[![codecov](https://codecov.io/gh/PeaceFounder/AppBundler.jl/graph/badge.svg?token=JE3S7HBN9X)](https://codecov.io/gh/PeaceFounder/AppBundler.jl)

![](docs/assets/appbundler.png)

From the dawn of time, software developers have been concerned about the distribution of their software. In the beginning, executables distributed over floppy disks were sufficient. However, as time progressed, we needed nicer installers with desktop integration for launching and uninstalling, and hence installers were born. As time progressed, hard lessons were learned that access to all system resources is a security nightmare, and sandboxing of applications was introduced in all major operating systems.

Every operating system is different and has made unique design choices. On macOS, applications are simply put within the Applications folder from DMG containers. Windows uses many formats, with MSIX being the most modern approach, and Linux uses Snap and Flatpak for external software distribution. To create an installer on each of these platforms, there is a list of common tasks that one needs to perform individually:

- Make icon assets in a form that the installer/operating system understands
- Specify the needed capabilities for the application
- Set the launching endpoint, whether it is a GUI or a terminal application
- Bundle all configuration files with the application into the installer
- Perform code signing of the installer and possibly the application

Maintaining all these configuration nuances is hard. AppBundler resolves these issues with defaults that enable shipping GUI applications effortlessly while also enabling developers to simply configure the installer with their own configuration overlay in places where they need it, making the process much easier to debug and communicate about.

AppBundler, in contrast to other solutions, only uses open source tools for making installers that are available across platforms and are compiled in a cross-platform way with Julia's BinaryBuilder infrastructure. This makes it easy to see what sources were used in making the installers, maintain them, and be sure they don't contain malware, as you can reproduce the binaries yourself. The most important reason to use open source tools is that they can be bundled with the AppBundler project in a reproducible way across all operating systems and installed as a simple Julia package.

`AppBundler.jl` offers recipes for building Julia GUI applications in modern desktop application installer formats. It uses Snap for Linux, MSIX for Windows, and DMG for macOS as targets. It bundles the full Julia runtime within the app, which, together with artifact caching stored in scratch space, allows the bundling to be done quickly, significantly shortening the feedback loop.

## Introduction

To use AppBundler on a Julia application project, you need to use the standard package structure with a defined entry point `MyApp.@main`, which allows launching the application with `julia --project=. -e "using MyApp"`. Having this basic configuration allows setting up the bundling infrastructure with commands:

```julia
julia --project=meta
]add AppBundler
using AppBundler
AppBundler.install_github_workflow()
```

Optionally run `AppBundler.generate_signing_certificates()` for persistent signing certificates and take note of `MACOS_PFX_PASSWORD` and `WINDOWS_PFX_PASSWORD` that need to be specified as environment variables. Alternatively, you can obtain certificates from a trusted CA and place them under `meta/msix/certificate.pfx` and `meta/dmg/certificate.pfx` accordingly.

The build setup installs a `meta/build.jl` script in addition to `.github/workflows/Releases.yml`. Once the setup is done, you can build your project:

```bash
julia --project=meta meta/build.jl --build-dir=@temp --target-platform=linux|windows|macos|all --target-arch=aarch64|x86_64
```

See `--help` for all supported arguments. When arguments are skipped, the target platform and architecture are taken from the host system, and the build directory is a temporary directory.

The setup is designed such that `meta/build.jl` can be further modified by a user in case of custom bundling needs without needing to touch `.github/workflows/Releases.yml`. The custom `build.jl` can be useful for custom bundling specifications, customizing the bundling process itself, or for bundling custom products.

Once applications are launched they define a `USER_DATA` environment variable where apps can store their data. On Linux and Windows, those are designated application locations which get removed with the uninstallation of the app, whereas on macOS, apps use `~/.config/myapp` and `~/.cache/myapp` folders unless run from a sandbox, in which case the `$HOME/Library/Application Support/Local` folder will be used.

To see how this works, explore [AppBundler.jl/examples](https://github.com/PeaceFounder/AppBundler.jl/tree/main/examples).

## Examples

The following GUI frameworks have been tested with AppBundler across different platforms:

| Framework | Platform Support | Notes | Examples |
|-----------|-----------------|-------|----------|
| QML | ✓ All platforms | Fully supported | [PeaceFounderClient](https://github.com/PeaceFounder/PeaceFounderClient/releases) |
| GLFW | ✓ All platforms | Fully supported | none |
| Gtk/Mousetrap | ⚠ macOS, Linux | Does not launch on Windows | none |
| Makie | ⚠ All platforms | [GLMakie may not work on Windows](https://github.com/MakieOrg/Makie.jl/issues/5342) | [ImageColorThresholderApp](https://github.com/rakeshksr/ImageColorThresholderApp.jl/pull/4) |
| Blink | ⚠ All platforms | Requires heavy patching for relocability | [KomaMRI](https://github.com/JuliaHealth/KomaMRI.jl/pull/640) |
| Electron | ✓ All platforms | Fully supported | [BonitoBook](https://github.com/SimonDanisch/BonitoBook.jl/pull/34) |

## Installing Built Applications

*The following instructions are for end users installing your built applications.*

- **MSIX (Windows)**: If self-signed, go to MSIX bundle properties and add the certificate to the trusted certificate authorities first (see https://www.advancedinstaller.com/install-test-certificate-from-msix.html). Then double-click on the installer and install the app.
- **Snap (Linux)**: The snap can be installed from a command line: `snap install --classic --dangerous MyApp.snap`
- **DMG (macOS)**: If self-signed, you need to click on the app first, then go to `Settings -> Privacy & Security`, whitelisting the launch request. Then drag and drop the application to the `Applications` folder. Launch the application and go again to `Settings -> Privacy & Security` to whitelist it.

Note that all these extra steps are avoidable if you are willing to buy Windows and macOS code signing certificates. For Snap, you can try to submit the app to a snap store so it can be installed with a GUI.

## Bundling Applications

The highest level interface is:
```julia
build_app(Linux(:aarch64), source, "MyApp.snap"; precompile = true)
```

where the first argument specifies the platform. This command will take a Julia source project, compile modules, and then bundle them into the corresponding bundle format.

**Platform-Specific Examples:**
```julia
import AppBundler
import Pkg.BinaryPlatforms: Linux, Windows, MacOS

# Linux - Create a Snap package
AppBundler.build_app(Linux(:x86_64), "MyApp", "build/MyApp.snap")

# Windows - Create a MSIX installer
AppBundler.build_app(Windows(:x86_64), "MyApp", "build/MyApp.msix")

# macOS - Create a .app bundle
AppBundler.build_app(MacOS(:x86_64), "MyApp", "build/MyApp.app")

# macOS - Create a .dmg installer with automatic LZMA compression
AppBundler.build_app(MacOS(:x86_64), "MyApp", "build/MyApp.dmg")
```

The function automatically detects whether to create an installer based on the destination file extension. Precompilation is enabled by default and will error if it cannot be performed on the host system. For cross-platform building, you can disable precompilation with the `precompile=false` option. In the future, Julia may implement cross-compilation, which would make this option redundant.

**Lower-Level API:** For more control, use the lower level API:
```julia
product = JuliaAppBundle(source; precompile = true, incremental = false)
snap = Snap(source)
bundle(product, snap, destination)
```

Currently, only `JuliaAppBundle` compilation is supported. In the future, one will be able to specify the product to be `SysImage` (or another better name) to compile the application with `PackageCompiler` instead and perform corresponding bundling. There are also plans to experiment with JuliaC integration.

On the other end, we have the destination in which the product needs to be bundled. Here again, we have a variety to choose from if one were to add Deb, RPM, or Flatpak bundling formats. The `Snap` constructor takes the role of finding configuration files from the user directory and from the default AppBundler recipes folder that one can inspect. Similarly, `MSIX` and `DMG` constructors can be called (see docstrings).

**Custom Product Bundling:** In some situations, you may want to bundle a library which is not supported by the AppBundler product interface, or perhaps bundle other programming language projects like C, Rust, or Python applications. In such situations, you can use:
```julia
dmg = DMG(source)
bundle(dmg, destination) do app_stage
    # Compile project and install it in the appropriate directories of app_stage
end
```

In the future, AppBundler may add support for bundling Python and Rust projects directly.

## Staging

AppBundler offers a staging API for staging products. Currently, only `JuliaAppBundle` staging is supported:

```julia
pkg = JuliaAppBundle(app_dir; precompile = false)
stage(pkg, Linux(:x86_64), "build/linux_staging")
```

This performs the complete staging process for a Julia application, preparing it for distribution on the target platform. The process includes downloading the appropriate Julia runtime, copying application dependencies, retrieving artifacts, configuring startup files, and optionally precompiling the application.

Similar staging API will be made available with PackageCompiler and hopefully also with JuliaC integration.

It is also possible to stage application bundle files:

```julia
msix = MSIX(app_dir)
stage(msix, "build/msix_staging")
```

This is used internally in the `bundle` function and can be useful for debugging purposes.

## Templating

Configuration options for installer bundles vary greatly across platforms, making a single unified configuration file impractical. AppBundler addresses this through a recipe-based templating system that provides sensible defaults while allowing customization when needed.

AppBundler provides default configuration files that use simple variable substitution with `{{ MY_VAR }}` syntax. Variables are automatically derived from your `Project.toml` (name, version, etc.) or manually specified in a `[bundle]` section. This default setup covers most common use cases without requiring platform-specific knowledge.

When your application requires more control (such as accessing hardware, networking capabilities, or custom launchers), you can override defaults by placing custom configuration files in your `meta` folder: `meta/snap/snap.yaml` for Linux, `meta/msix/AppxManifest.xml` for Windows, or `meta/dmg/Entitlements.plist` for macOS. Additional bundle resources (like custom icon sizes) can be provided by placing them in the corresponding folder hierarchy within `meta`.

Common customization scenarios include sandboxing configuration (adding specific capabilities or interfaces your application needs), custom launchers (defining alternative entry points), and icon overrides (providing platform-specific icon assets in various sizes). By keeping templates simple and encouraging users to copy and modify complete configuration files rather than creating complex nested templates, AppBundler makes platform-specific customization straightforward and debuggable.

## Troubleshooting and Known Limitations

Currently, Julia does not cross-compile, except for macOS where `:aarch64` can also run `:x86_64` applications. Hence, one needs to have the host as a target, which nowadays can be easy to get via continuous integration infrastructure like GitHub, GitLab, etc. The bundling, however, is cross-platform compatible, where UNIX hosts can generate all compatible installers, which may be relevant for other programming language projects. A releated issue is reliance on `deps/build.jl` script which may cause issues.

Another set of issues comes from sandboxing, where each of the installer formats enforces its own way to isolate the running application from the system resources. This requires careful configuration of the parameters and patience in debugging issues and coming up with workarounds. Sandboxing is often expected for app stores for the application to receive a positive review. Currently, only macOS sandboxing with a special trick seems to work, whereas Snap only works for GTK applications, and MSIX is completely broken for Julia due to `msvcrt32.dll` runtime library use over the more modern `ucrt.dll`.

### Snap (Linux)

- Confinement for some reason does not work for OpenGL applications (see issue https://github.com/JuliaGraphics/QML.jl/issues/191)

To debug issues with snap packaging, stop at the staging directory stage and install it with `snap try myapp_dir`. Further, you can also enter the shell of the application for inspecting the sandboxing behavior more closely with `snap run --shell myapp`.

### DMG (macOS)

- For some reason, `com.apple.coreservices.launchservicesd` needs to be added as an exception when sandbox is enabled, which may deserve a closer inspection in the future.
- macOS applications also need to be notarized. `rcodesign` can support that. The question is what the API should be for the user here.

To debug the DMG bundles, compression is not necessary, and one can stop at the staging directory stage and skip compression.

### MSIX (Windows)

- GTK applications fail to find shared libraries in the UWP environment. This will probably be resolved once we get Julia with the `ucrt.dll` runtime.
- Only runtime behavior `packagedClassicApp` is supported. This is because of `msvcrt32.dll` reliance, which will be resolved once Julia transitions to `ucrt.dll`.
- When OpenSSL is installed in the `C:\Windows\System32` folder, `osslsigncode` fails as system-wide OpenSSL takes precedence over Julia's packaged `OpenSSL_jll`. 

To debug issues with MSIX, you can stop bundling at a folder stage and test it with `Add-AppPackage -register AppxManifest.xml`.

## Acknowledgments

This work is supported by the European Union in the Next Generation Internet initiative ([NGI0 Entrust](https://ngi.eu/ngi-projects/ngi-zero-entrust/)), via NLnet [Julia-AppBundler](https://nlnet.nl/project/Julia-AppBundler/) project.
