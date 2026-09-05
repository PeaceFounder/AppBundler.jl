# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0]

### Added

- `Tarball` bundle format producing a relocatable, unsigned `.tar.gz` for Linux, macOS and Windows,
  with `install.sh` / `install.ps1`, a `bin/` launcher and a `.desktop` entry
  ([#36](https://github.com/PeaceFounder/AppBundler.jl/pull/36)).
- `--target-bundle=tarball` and `--target-os` command line options ([#36](https://github.com/PeaceFounder/AppBundler.jl/pull/36)).
- `juliaimg_strip_debug` and `juliaimg_strip_docs` preferences for smaller images
  ([#36](https://github.com/PeaceFounder/AppBundler.jl/pull/36)).
- `AppBundler.Juliaup` module for publishing distributions through `juliaup`
  ([#43](https://github.com/PeaceFounder/AppBundler.jl/issues/43)). It writes the version database
  for all 13 client target triples plus the four `*DBVERSION` pointer files, mirrors the upstream
  database so stock channels keep working, and resolves the database version above the public one so
  clients do not silently ignore it.
- `appbundler juliaup <project_dir>` command building that static site, and
  `AppBundler.install_juliaup_workflow()` installing a GitHub Actions workflow that builds the
  tarballs, attaches them to the release and deploys the database to GitHub Pages.
- Client wrappers (`<app>-juliaup`, `<app>-julia`, and PowerShell equivalents) that point
  `JULIAUP_SERVER` at the distribution and isolate `JULIAUP_DEPOT_PATH`, leaving a stock `juliaup`
  installation untouched.
- Documentation for the whole workflow in `docs/src/juliaup.md`, including the two silent failure
  modes: a database version at or below the public one is ignored without any diagnostic, and a
  client on `dev` or `releasepreview` reads a different pointer file.
- `llms.txt` and `llms-full.txt` generated with the documentation.

### Changed

- A tarball's canonical name now carries the operating system
  (`<app>-<version>-<os>-<arch>.tar.gz`). Without it a release matrix uploads one archive per
  platform under the same asset name and the `juliaup` database cannot tell them apart.

### Fixed

- `TarPack.pack` reported `ArgumentError: Collection has multiple elements` instead of its own
  explanatory error when the staging directory held more than one entry.
- `--target-bundle=tarball` raised a `MethodError` when combined with the `juliac` bundler; a
  `JuliaCBundle` can now be packaged as a tarball like the other formats.

## [1.0.1]

Releases up to and including 1.0.1 predate this changelog; see the
[commit history](https://github.com/PeaceFounder/AppBundler.jl/commits/main) for details.

[Unreleased]: https://github.com/PeaceFounder/AppBundler.jl/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/PeaceFounder/AppBundler.jl/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/PeaceFounder/AppBundler.jl/releases/tag/v1.0.1
