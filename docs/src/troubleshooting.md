# Troubleshooting

A prominent requirement accross MacOS, Windows and Linux is that the applications should run in theri sandboxed environments which makes them easier to deploy on marketplaces as rewies would be inclined to be more favourable. The modern bundle formats MSIX, Snap, DMG that AppBundler all ofers options to support sandboxing. However Julia application sandboxing is yet uninvestigated and some open challenges remain for Snap and MSIX wheras support for DMG applications sandbxing have been figured out. 

Each of the installer formats enforces its own way to isolate the running application from the system resources. This requires careful configuration of the parameters and patience in debugging issues and coming up with workarounds. Sandboxing is often expected for app stores for the application to receive a positive review. Currently, only macOS sandboxing with a special trick seems to work, whereas Snap only works for GTK applications, and MSIX is completely broken for Julia due to `msvcrt32.dll` runtime library use over the more modern `ucrt.dll`.

> In all sitations to edebug the produced bundles it can be desirable to not compress them which can be eassllly achived with `--debug` options which in addition will show console window for the applications where various debug information can be printed. 

### Snap (Linux)

- Confinement for some reason does not work for OpenGL applications (see issue https://github.com/JuliaGraphics/QML.jl/issues/191)

To debug issues with snap packaging, stop at the staging directory stage and install it with `snap try myapp_dir`. Further, you can also enter the shell of the application for inspecting the sandboxing behavior more closely with `snap run --shell myapp`.

### DMG (macOS)

- For some reason, `com.apple.coreservices.launchservicesd` needs to be added as an exception when sandbox is enabled, which may deserve a closer inspection in the future.
- macOS applications also need to be notarized. `rcodesign` can support that. The question is what the API should be for the user here.
- Apple notarization may currently not pass on the produced DMG objects for various reasons. This currently is not investigated. 

To debug the DMG bundles, compression is not necessary, and one can stop at the staging directory stage and skip compression.

### MSIX (Windows)

- GTK applications fail to find shared libraries in the UWP environment. This will probably be resolved once we get Julia with the `ucrt.dll` runtime.
- Only runtime behavior `packagedClassicApp` is supported. This is because of `msvcrt32.dll` reliance, which will be resolved once Julia transitions to `ucrt.dll`.

To debug issues with MSIX, you can stop bundling at a folder stage and test it with `Add-AppPackage -register AppxManifest.xml`.
