# AppBundler.jl
[![codecov](https://codecov.io/gh/PeaceFounder/AppBundler.jl/graph/badge.svg?token=JE3S7HBN9X)](https://codecov.io/gh/PeaceFounder/AppBundler.jl)

![](docs/src/assets/appbundler.png)

AppBundler.jl is a Julia package that enables cross-platform native installer generation — MSIX, Snap, and DMG — from a single UNIX host, eliminating the need for per-platform build environments. It achieves this by replacing host system utilities with cross-compiled, open-source tools distributed through Julia's Yggdrasil registry, resulting in a consistent and reproducible packaging pipeline.

The package provides a clean API for bundling any Julia application exposing `@main` or distribution, with support for icons, configuration files, and native customization. GitHub Actions workflows allow multi-platform installer builds to be triggered with a single click, making continuous delivery of native installers practical for open-source Julia projects. AppBundler can also be useful for bundling applications written in other build projects (see docs).

# Showcase

AppBundler builds Snap, MSIX and DMG using opens source tools that are available accorss all unix platofrms Linux, MacOS, FreeeBSD while also being able to build MSIX on windows itslef. The following videos demonstrates the resulting DMG and MSIX installers that are priduced via AppBundler. 

| [![Video 1](https://img.youtube.com/vi/plVW30qU9SQ/maxresdefault.jpg)](https://www.youtube.com/watch?v=plVW30qU9SQ) | [![Video 2](https://img.youtube.com/vi/cjGV5itF4TE/maxresdefault.jpg)](https://www.youtube.com/watch?v=cjGV5itF4TE&t=144s) |
|:---:|:---:|
| DMG | MSIX |

> Note The API for bundling have changed since creation of the vidoe demonstrations, but the pipeline composition and the resulting bundles have remained the same. 


The following GUI frameworks have been tested with AppBundler across different platforms:

| Framework | Platform Support | Notes | Examples |
|-----------|-----------------|-------|----------|
| QML | ✓ All platforms | Fully supported | [PeaceFounderClient](https://github.com/PeaceFounder/PeaceFounderClient/releases) |
| GLFW | ✓ All platforms | Fully supported | none |
| Gtk/Mousetrap | ⚠ macOS, Linux | Does not launch on Windows | none |
| Makie | ⚠ All platforms | [GLMakie may not work on Windows](https://github.com/MakieOrg/Makie.jl/issues/5342) | [ImageColorThresholderApp](https://github.com/rakeshksr/ImageColorThresholderApp.jl/pull/4) |
| Blink | ⚠ All platforms | Requires heavy patching for relocability | [KomaMRI](https://github.com/JuliaHealth/KomaMRI.jl/pull/640) |
| Electron | ✓ All platforms | Fully supported | [BonitoBook](https://github.com/SimonDanisch/BonitoBook.jl/pull/34) |

For each framework also see coresponding minimal example application in the [examples folder](https://github.com/PeaceFounder/AppBundler.jl/tree/main/examples). Note that you can copy them easilly from `pkgdir(AppBundler)` once AppBundler is installed. 

On top of that with AppBundler one can also build Julia distributions as demsontrated in [Jumbo Julia](https://github.com/JanisErdmanis/Jumbo). Futhermore bundling can be done with JuliaC including the new `--trim` feature with support of selective asset resultion relative to package directories as long as `pkgdir(@__MODULE__)` is used and `AppEnv.init()` is called at runtime to initalize the index.

# Overview

AppBundler can be installed as a Julia applciation:
```
]app add AppBundler
```
Once installed ensure that `~/.julia/bin` is in your PATH. 


Let's say you have a Julia applicaation that exposes `@main` and you can laucnh your application with `julia --project=. -m MyApp` then your application is ready for the bundling which can be done as simple as:
```
appbundler build . --build-dir=build --selfsign
```
which will build the application accordingly for the current platform. 

AppBundler offers extensive options for compilation. Whether the application is compiled from pkgimages which makes the compilations faster or with sysimage generation. Or alternativelly one can opt for JuliaC applicaiton compilation to reduce the installers size. Futhermore how the applications behave at runtime are also customizable, whether they are sandboxed, whether terminal is showed, the parameters and the look of the installers for each individual platform. 


## Installing Built Applications

*The following instructions are for end users installing your built applications.*

- **MSIX (Windows)**: If self-signed, go to MSIX bundle properties and add the certificate to the trusted certificate authorities first (see https://www.advancedinstaller.com/install-test-certificate-from-msix.html). Then double-click on the installer and install the app.
- **Snap (Linux)**: The snap can be installed from a command line: `snap install --classic --dangerous MyApp.snap`
- **DMG (macOS)**: If self-signed, you need to click on the app first, then go to `Settings -> Privacy & Security`, whitelisting the launch request. Then drag and drop the application to the `Applications` folder. Launch the application and go again to `Settings -> Privacy & Security` to whitelist it.

Note that all these extra steps are avoidable if you are willing to buy Windows and macOS code signing certificates. For Snap, you can try to submit the app to a snap store so it can be installed with a GUI.

## Acknowledgments

This work is supported by the European Union in the Next Generation Internet initiative ([NGI0 Entrust](https://ngi.eu/ngi-projects/ngi-zero-entrust/)), via NLnet [Julia-AppBundler](https://nlnet.nl/project/Julia-AppBundler/) project.
