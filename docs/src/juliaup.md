# Juliaup

Installers are the right shape for a desktop application, but a bundled Julia *distribution* — a
runtime with your packages already baked in — is better delivered the way Julia itself is: through
`juliaup`. Users then get

```
juliaup add myapp-1.2.0
julia +myapp-1.2.0
```

and a single command to move to the next release.

This needs no fork of `juliaup` and no dedicated infrastructure. `juliaup` downloads from whatever
host `JULIAUP_SERVER` points at, so publishing a distribution is a matter of putting a handful of
static files somewhere — GitHub Pages is enough — while the tarballs themselves stay on your
releases page. This is the same approach JuliaHub uses to distribute Dyad.

## What juliaup actually does

`juliaup add <channel>` makes three requests, and only the first two touch your site:

1. `GET <server>/juliaup/RELEASECHANNELDBVERSION` — one line, the number of the current database.
2. `GET <server>/juliaup/versiondb/versiondb-<dbversion>-<target>.json` — the database, cached
   locally afterwards.
3. `GET <UrlPath>` — the tarball, at the path the database recorded for the resolved version.

Steps between those are local lookups: the channel resolves to a full version string in
`AvailableChannels`, which resolves to a `UrlPath` in `AvailableVersions`. The archive is then
unpacked into `~/.julia/juliaup/julia-<fullversion>/`.

`UrlPath` is resolved against the server base, which is what makes both layouts possible:

- a **relative** path (`assets/myapp-1.2.0-linux-x86_64.tar.gz`) keeps the database portable — move
  the whole site to another host and nothing has to be rewritten;
- an **absolute** url points somewhere else entirely, so a database on GitHub Pages can serve
  tarballs from your GitHub releases page without a single byte passing through Pages.

## Publishing

Build a tarball for each platform, then publish the database:

```
appbundler build . --target-bundle=tarball --build-dir=build
appbundler juliaup . --build-dir=site \
    --server=https://acme.github.io/myapp \
    --asset-base=https://github.com/acme/myapp/releases/download/v1.2.0 \
    --platform=linux/x86_64 --platform=macos/aarch64 \
    --wrappers
```

which writes

```
site/juliaup/DBVERSION
site/juliaup/RELEASECHANNELDBVERSION
site/juliaup/RELEASEPREVIEWCHANNELDBVERSION
site/juliaup/DEVCHANNELDBVERSION
site/juliaup/versiondb/versiondb-<dbversion>-<target>.json   (13 files)
site/wrappers/myapp-juliaup, myapp-julia, and the PowerShell equivalents
```

Serve that over HTTPS and the distribution is installable.

The equivalent Julia API is [`AppBundler.Juliaup.publish`](@ref):

```julia
using AppBundler

dist = Juliaup.JuliaupDistribution(".";
                                   server = "https://acme.github.io/myapp",
                                   asset_base = "https://github.com/acme/myapp/releases/download/v1.2.0")

Juliaup.publish(dist, "site"; assets = [(:linux, :x86_64), (:macos, :aarch64)])
```

## Mirroring

By default AppBundler *mirrors*: it downloads the upstream database, merges your channels into it,
and republishes the result. Your users keep `release`, `lts` and every stock channel while pointed
at your server. This is what JuliaHub does — their linux-x64 database is the public one plus their
own entries.

Pass `--no-mirror` to publish your channels alone. That is the right choice for an air-gapped site,
where reaching `julialang-s3.julialang.org` at publish time is not possible, at the cost of stock
Julia channels no longer resolving for anyone using your server.

## Continuous delivery

`AppBundler.install_juliaup_workflow()` drops a GitHub Actions workflow into
`.github/workflows/Juliaup.yml`. It builds a tarball on a matching runner per platform, attaches
them to the release, and deploys the database to GitHub Pages. Enable Pages for the repository with
*GitHub Actions* as the source, and each release republishes the distribution.

## Two failure modes worth knowing

Both are silent, which is what makes them expensive.

**A database version at or below the public one is ignored.** `juliaup` replaces its cached
database only when the number it reads exceeds *both* the number compiled into its own binary and
its local copy — and it logs nothing when it does not. Your channels simply never appear. Always
publish above the public number; AppBundler resolves this for you by checking upstream, and the
bundled workflow additionally seeds the previously published number so republishing keeps climbing.

**All four pointer files must agree.** `juliaup` reads exactly one of them, depending on the channel
it was itself installed from: `release` clients read `RELEASECHANNELDBVERSION`, `releasepreview`
clients `RELEASEPREVIEWCHANNELDBVERSION`, `dev` clients `DEVCHANNELDBVERSION`. AppBundler writes all
four with the same number, so a user on a preview client does not take a 404 on a database your
mirror never wrote.

## Target triples

A database file is named after the Rust target triple of the **`juliaup` client binary**, not the
Julia build it installs. There are 13, and AppBundler writes all of them. Two consequences are easy
to get wrong by hand:

- The Linux `juliaup` is a musl-static binary that also runs on glibc hosts, so a Linux build has to
  appear in both the `-musl` and `-gnu` databases. The same holds for the Windows `-gnu`/`-msvc`
  pair. Upstream publishes these as identical files.
- A database carries every architecture its client can *execute*. A 64 bit client lists 32 bit
  builds, and an Apple Silicon client lists x86_64 builds so they can run under Rosetta 2.

## Version strings

A version is identified by a string like `1.12.7+myapp-1x2x0.x64.linux.gnu`: the Julia version, then
build metadata whose components are the build tag, architecture, vendor and operating system.

`juliaup` splits that metadata on `.` and reads the **second** component as the architecture, so a
build tag containing dots shifts the index and the entry resolves to a nonsense architecture.
JuliaHub hit this with early Dyad releases — `1.11.8+dyad-2.1.0-rc3.x64.linux.gnu` parses its
architecture as `1` — and later switched to `dyad-2x1x0-rc3`. AppBundler sanitises the tag for you,
which is why `myapp-1.2.0` becomes `myapp-1x2x0`.

## Client wrappers

`--wrappers` writes small scripts that set `JULIAUP_SERVER` and, importantly,
`JULIAUP_DEPOT_PATH`:

```bash
export JULIAUP_SERVER=https://acme.github.io/myapp
export JULIAUP_DEPOT_PATH="${HOME}/.julia/juliaup-depots/acme.github.io"

exec juliaup "$@"
```

The isolated depot keeps your distribution and the user's stock `juliaup` from sharing channels or
state, so `myapp-juliaup status` and `juliaup status` list different things and neither can disturb
the other. Users who prefer not to install wrappers can export the same two variables themselves.

## Known limitation

A distribution installed through `juliaup` is launched as `julia`, not through the `bin/<app>`
launcher the tarball also ships. That launcher is what normally sets `USER_DATA`, and without it
AppEnv falls back to a temporary depot on Linux, so packages a user adds on top of the distribution
do not persist between sessions. Setting `USER_DATA` in the environment restores persistence.

## API

```@docs
AppBundler.Juliaup
AppBundler.Juliaup.JuliaupDistribution
AppBundler.Juliaup.publish
AppBundler.Juliaup.install_wrappers
AppBundler.Juliaup.VersionDB
AppBundler.Juliaup.read_versiondb
AppBundler.Juliaup.write_versiondb
AppBundler.Juliaup.add_version!
AppBundler.Juliaup.add_channel!
AppBundler.Juliaup.next_dbversion
AppBundler.Juliaup.fetch_versiondb
AppBundler.Juliaup.fetch_upstream
AppBundler.Juliaup.full_version_string
AppBundler.Juliaup.sanitize_build_tag
AppBundler.Juliaup.platform_suffix
AppBundler.Juliaup.targets_for
AppBundler.install_juliaup_workflow
```
