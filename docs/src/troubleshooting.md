# Troubleshooting

Sandboxed execution is a requirement across macOS, Windows, and Linux for distribution through official app marketplaces, where confinement is typically a prerequisite for approval. AppBundler supports sandboxing for all three bundle formats — MSIX, Snap, and DMG. Sandbox support for Julia applications is not yet fully resolved: MSIX and Snap both have known open issues, while DMG sandboxing has a working solution.

Each format implements isolation through its own mechanism, requiring format-specific configuration. Currently, macOS sandboxing is functional via the workaround described below; Snap confinement is limited to GTK applications; and MSIX sandboxing is non-functional for Julia applications due to a dependency on the legacy `msvcrt32.dll` runtime, which is incompatible with the UWP execution model.

> To facilitate debugging, bundle compression can be disabled via the `--debug` flag. This also enables a console window through which stdout/stderr output is surfaced.

### Snap (Linux)

- Snap confinement is currently broken for OpenGL applications; the root cause is unknown (see [JuliaGraphics/QML.jl#191](https://github.com/JuliaGraphics/QML.jl/issues/191)).

To debug Snap packages, skip compression and install the staging directory directly. Optionally, inspect the sandbox environment of the installed application:
```
snap try myapp_dir       # install unpackaged directory
snap run --shell myapp   # inspect sandbox environment interactively
```

### DMG (macOS)

- `com.apple.coreservices.launchservicesd` must be whitelisted as a sandbox exception; the underlying reason is not yet understood.
- Notarization is required for macOS distribution and can be performed with `rcodesign`.
- Deep signing (`dmg_shallow_signing=false`) may intermittently fail; if so, clean the staging directory and retry. For custom cleanup logic, use the public API as described in [Reference](reference.md).
- Notarization may fail due to an incompatible directory structure or unsigned artifacts; this has not yet been fully investigated.

To debug DMG bundles, skip the compression step. Note that the staging directory must carry a `.app` extension for macOS to treat it as an application bundle.

### MSIX (Windows)

- GTK applications fail to resolve shared libraries within the UWP execution environment. This is expected to be resolved once Julia migrates to the `ucrt.dll` runtime.
- Only the `packagedClassicApp` execution mode is supported due to Julia's `msvcrt32.dll` dependency. This constraint will be lifted once Julia transitions to `ucrt.dll`.

To debug MSIX packages, skip compression and register the manifest from the staging directory directly:

```
Add-AppPackage -register AppxManifest.xml
```
