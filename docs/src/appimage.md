# AppImage

An AppImage is a single executable file that is **mounted** rather than installed. For a Julia
application this matters more than it might seem: a bundled distribution is tens of thousands of
small files, and writing all of them onto a network filesystem is the slow part of every other
format. On HPC clusters that cost — sometimes called the hydration problem — is what stops people
distributing Julia applications as archives at all. An AppImage never unpacks, so it does not pay it.

```
appbundler build . --target-bundle=appimage --build-dir=build
```

produces `build/<app>-<version>-<arch>.AppImage`, which a user makes executable and runs. There is
nothing to install and nothing to clean up afterwards.

## How the format works

An AppImage is a **runtime ELF followed by a squashfs image**. The runtime knows the filesystem
begins immediately after itself, mounts it through FUSE, and executes `AppRun` from the mount
point. That is the whole format — there is no container, no manifest, and no package database.

AppBundler stages an AppDir, then has `mksquashfs` write the filesystem straight into the output
file after a reserved prefix, and finally writes the runtime into that prefix. Building the
squashfs separately and concatenating would need a second full-size temporary copy, which for a
Julia distribution is hundreds of megabytes.

The staged AppDir looks like this:

```
AppRun                                          entry point, execs bin/julia
<app>.desktop                                   Icon=<app>, no path, no extension
<app>.png
.DirIcon                                        what file managers read for the thumbnail
usr/share/applications/<app>.desktop            menu integration once installed
usr/share/icons/hicolor/256x256/apps/<app>.png
usr/share/metainfo/<id>.appdata.xml             AppStream metadata
bin/ lib/ share/ etc/                           the Julia distribution
```

The payload is compressed with **zstd** by default. `gzip` and `xz` also work — the runtime links
squashfuse against zstd and zlib, and squashfuse handles xz — but zstd decompresses far faster,
which is the point of mounting in the first place. `lz4` is deliberately rejected: `mksquashfs`
offers it, and the runtime cannot read it.

## Obtaining the runtime

The runtime is a ~900 KB static binary. There is no jll for it yet — packaging one means first
packaging `libfuse` and `squashfuse`, neither of which exists in Yggdrasil — so for now point
AppBundler at a runtime you obtained yourself:

```toml
# LocalPreferences.toml
[AppBundler]
appimage_runtime = "/path/to/runtime-x86_64"
```

or pass it directly:

```julia
AppImage(app_dir; runtime = "/path/to/runtime-x86_64")
```

Signed runtimes are published at
[AppImage/type2-runtime](https://github.com/AppImage/type2-runtime/releases). Prefer a dated tag
over `continuous` so your builds stay reproducible.

Once `AppImageRuntime_jll` is registered, leaving `appimage_runtime` empty will pick it up
automatically. Note that a jll provides the artifact for the host platform, so building an AppImage
for another architecture still needs an explicit path.

## Build-time disk space

The AppDir is staged uncompressed before it is packed, so building an AppImage of a Julia
distribution needs a couple of gigabytes of working space. Julia stages into `TMPDIR`, which on
many systems is a `tmpfs` sized well below that, and `mksquashfs` reports exhaustion only as
`FATAL ERROR: Probably out of space on output filesystem`. If you hit that, point `TMPDIR` at a
real filesystem:

```
TMPDIR=/var/tmp appbundler build . --target-bundle=appimage --build-dir=build
```

## Where the depot goes

The mounted filesystem is read-only and disappears when the application exits, so the Julia depot
has to live somewhere else. Two options, selected with the `appimage_depot` preference:

- **`"app"`** (default) — `AppRun` points `USER_DATA` at `$XDG_DATA_HOME/<app>`, falling back to
  `~/.local/share/<app>`. The application gets a persistent per-user depot and the host's `~/.julia`
  is never touched.
- **`"julia"`** — the stock depot is left as Julia found it, with the bundled `share/julia`
  appended so the shipped packages stay resolvable. Choose this where users expect the application
  to see the environments they already have, which is common on HPC.

## FUSE

Mounting needs `fusermount` on the machine running the AppImage. Where it is missing the runtime
says so and suggests `--appimage-extract-and-run`, which extracts to a temporary directory first —
correct, but it gives up the property that made the format attractive.

If your target machines lack FUSE, the payload can be read directly, since it is an ordinary
squashfs at a known offset:

```julia
using AppBundler
AppBundler.AppImagePack.unpack("MyApp-1.0.0-x86_64.AppImage", "extracted/")
```

or, outside Julia:

```
unsquashfs -o $(./MyApp-1.0.0-x86_64.AppImage --appimage-offset) -d extracted MyApp-1.0.0-x86_64.AppImage
```

`--appimage-offset` and `AppBundler.AppImagePack.offset` return the same number: the size of the
runtime prefix.

## API

```@docs
AppBundler.AppImagePack
AppBundler.AppImagePack.pack
AppBundler.AppImagePack.offset
AppBundler.AppImagePack.unpack
AppBundler.AppImageRuntime
AppBundler.AppImageRuntime.resolve
AppBundler.bundle(::AppBundler.JuliaImgBundle, ::AppBundler.AppImage, ::String)
```
