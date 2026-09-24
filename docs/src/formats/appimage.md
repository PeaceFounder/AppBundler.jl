# AppImage

!!! warning "Experimental"
    AppImage bundling is experimental. Its API, defaults, and on-disk layout may change in any release without deprecation, and existing build scripts or bundles may stop working.


AppImage is a single executable file for Linux that is **mounted** rather than installed. It suits applications made of thousands of small files, which are slow to unpack and hydrate on the network filesystems used by HPC clusters.

## Build pipeline

An AppImage is a runtime ELF followed by a squashfs image. The runtime locates the filesystem directly after itself, mounts it through FUSE, and executes `AppRun` from the mount point. There is no container, no manifest, and no package database.

```sh
AppDir → mksquashfs → runtime → MyApp.AppImage
```
AppBundler has `mksquashfs` write the filesystem straight into the output file after a reserved prefix, then writes the runtime into that prefix. 

Runtimes are currently downloaded from [AppImage/type2-runtime](https://github.com/AppImage/type2-runtime/releases).

> Future releases will retrieve runtimes through `AppImageRuntime_jll` to keep builds reproducible in the long term.

## Package contents

The staged AppDir holds the application payload and a single entry point, `AppRun`, which the runtime executes from the mount point. AppBundler generates `AppRun` from a template that can be overridden in `meta/appimage/AppRun.sh`.

The AppImage specification also defines desktop integration files such as `myapp.desktop`, `myapp.png`, and `.DirIcon`. In practice, AppImage desktop integration has never matured and these files have little effect, so AppBundler does not generate them.

## Installation

An AppImage needs no installation: make it executable with `chmod +x` and run it. Mounting requires `fusermount` on the target machine. Where it is missing, the runtime suggests `--appimage-extract-and-run`, which extracts to a temporary directory first. 

### User data

The mounted filesystem is read-only and disappears when the application exits. Without an installation step, an AppImage cannot tell whether it is run once or kept long-term. By default, user data, including `JULIA_DEPOT_PATH`, therefore goes to a temporary directory. To keep it, set `USER_DATA`:

```sh
USER_DATA=~/mydata ./myapp.AppImage
```

To make this permanent, move the AppImage to `~/Applications` and add an alias to your shell profile:

```sh
alias myapp='USER_DATA=~/mydata ~/Applications/myapp.AppImage'
```
For further customisation, edit `AppRun` during packaging, for example to set `USER_DATA` to `$XDG_DATA_HOME/<app>`.

### Extraction

Since the payload is an ordinary squashfs at a known offset, it can be extracted directly, for example where FUSE is unavailable or to inspect the contents:
```sh
unsquashfs -o $(./MyApp-1.0.0-x86_64.AppImage --appimage-offset) -d extracted MyApp-1.0.0-x86_64.AppImage
```
`--appimage-offset` and `AppBundler.AppImagePack.offset` both return the size of the runtime prefix.

> Future releases will also support extraction with `appbundler unpack`.

## API

```@docs
AppBundler.AppImage
```
