# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0]

### Added

- `AppImage` bundle format, producing a single mountable file rather than an installed tree
  ([#42](https://github.com/PeaceFounder/AppBundler.jl/issues/42)). Because the payload is mounted
  instead of unpacked, a bundled Julia distribution never writes its tens of thousands of files to
  disk — the cost that makes other formats impractical on HPC filesystems.
- `--target-bundle=appimage` command line option.
- `AppBundler.AppImagePack`, with `pack`, `offset` and `unpack`. `unpack` reads the squashfs payload
  directly, which is the fallback for machines without a usable FUSE.
- `AppBundler.AppImageRuntime`, resolving the runtime binary from an explicit path, the
  `appimage_runtime` preference, or `AppImageRuntime_jll` once that package is registered.
- `appimage_depot` preference selecting where a Julia payload keeps its depot: `"app"` (default)
  points `USER_DATA` at `$XDG_DATA_HOME/<app>` and leaves the host `~/.julia` untouched, `"julia"`
  keeps the stock depot for sites where users expect their existing environments.
- `appimage_compression` preference (`zstd` by default, `gzip` and `xz` also accepted).
- Documentation in `docs/src/appimage.md`, covering the format, the runtime, the depot choice, the
  build-time space requirement, and the FUSE requirement together with the no-FUSE workaround.

### Changed

- `bundle(::Function, ::MSIX, ::String)` now has a docstring; it was empty and rendered blank in
  the manual.

## [1.0.1]

Releases up to and including 1.0.1 predate this changelog; see the
[commit history](https://github.com/PeaceFounder/AppBundler.jl/commits/main) for details.

[Unreleased]: https://github.com/PeaceFounder/AppBundler.jl/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/PeaceFounder/AppBundler.jl/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/PeaceFounder/AppBundler.jl/releases/tag/v1.0.1
