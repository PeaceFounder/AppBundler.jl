# Reference

AppBundler is structured around two concepts: a **product spec**, which describes how to build a Julia application, and a **bundle format**, which describes how to package it for distribution on a target platform. These are combined through the `bundle` function:

```julia
bundle(spec, format, destination; password = "")
```

This is also the function exposed to the command-line API, where command-line parameters configure the `spec` and format fields.

## Product Specs

A product spec defines how the application is compiled or staged. There are two kinds:

```julia
spec = JuliaImgBundle(project; kwargs...)  # stages a self-contained Julia image
spec = JuliaCBundle(project; kwargs...)    # compiles a native executable via juliac
```

Both specs can be staged directly into a directory for inspection before packaging via `stage(spec, destination)`. For `JuliaImgBundle`, staging is platform-agnostic as long as compilation is not required — cross-platform staging is possible by setting `precompile=false` and `sysimg_packages = []`, with the target platform specified via the `platform` keyword (defaults to `HostPlatform()`). For `JuliaCBundle`, the platform is fixed to the host, as determined by the `juliac` executable on `PATH`.

## Bundle Formats

A bundle format defines the packaging target. The three supported formats are `DMG` (macOS), `MSIX` (Windows), and `Snap` (Linux). They are instantiated from a project directory:

```julia
dmg  = DMG(project; arch = Sys.ARCH, kwargs...)
msix = MSIX(project; arch = Sys.ARCH, kwargs...)
snap = Snap(project; arch = Sys.ARCH, kwargs...)
```

Each format reads configuration file overrides from the corresponding `project/meta/<format>` directory and carries architecture information that determines the destination platform. Bundle formats can also be staged independently via `stage(format, destination)` to produce the directory structure before compression and signing.

### Low-Level Bundle API

For packaging non-Julia applications, or when you need full control over what goes into the bundle, the lower-level `bundle` do-block API can be used directly:

```julia
bundle(format, destination; password = "") do staging_dir
    # copy or compile application files into staging_dir
end
```

The `password` argument is the certificate password used to decrypt the signing certificate and perform code signing during the pack step. Non-Julia applications can be bundled this way as well, as long as the user takes care of building and installing the application files in the setup callback.

## Types

```@docs
AppBundler.JuliaImg.JuliaImgBundle
AppBundler.JuliaC.JuliaCBundle
AppBundler.DMG
AppBundler.MSIX
AppBundler.Snap
```

## Functions

```@docs
AppBundler.bundle(::AppBundler.JuliaImgBundle, ::AppBundler.DMG, ::String)
AppBundler.stage(::AppBundler.JuliaImg.JuliaImgBundle, ::String)
AppBundler.stage(::AppBundler.JuliaC.JuliaCBundle, ::String)
AppBundler.bundle(::Function, ::AppBundler.DMG, ::String)
AppBundler.stage(::AppBundler.MSIX, ::String)
```
