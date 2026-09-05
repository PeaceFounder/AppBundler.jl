import JSON
import Downloads

"""
Rust target triples for which `juliaup` publishes a version database.

The triple identifies the *`juliaup` client binary*, not the Julia build it installs. Each client
downloads `versiondb-<dbversion>-<target>.json` and nothing else, so a distribution must be
written into every target a prospective user might run. Notably the Linux client is a
musl-static binary that also runs on glibc hosts, which is why both variants exist and carry
identical content upstream.
"""
const JULIAUP_TARGETS = ["aarch64-apple-darwin",
                         "aarch64-unknown-linux-gnu",
                         "aarch64-unknown-linux-musl",
                         "i686-pc-windows-gnu",
                         "i686-pc-windows-msvc",
                         "i686-unknown-linux-gnu",
                         "i686-unknown-linux-musl",
                         "x86_64-apple-darwin",
                         "x86_64-pc-windows-gnu",
                         "x86_64-pc-windows-msvc",
                         "x86_64-unknown-freebsd",
                         "x86_64-unknown-linux-gnu",
                         "x86_64-unknown-linux-musl"]

"""
Pointer files naming the database version currently published.

`juliaup` reads exactly one of these depending on the channel it was itself installed from
(`release`, `releasepreview` or `dev`), so all of them must be written and must agree. Upstream
carries no `DEVPREVIEWCHANNELDBVERSION`, and a client whose pointer file is missing fails with a
404 on a database the mirror never wrote.
"""
const DBVERSION_FILES = ["DBVERSION",
                         "RELEASECHANNELDBVERSION",
                         "RELEASEPREVIEWCHANNELDBVERSION",
                         "DEVCHANNELDBVERSION"]

"""
Default server `juliaup` downloads from when `JULIAUP_SERVER` is unset.
"""
const DEFAULT_SERVER = "https://julialang-s3.julialang.org"

# Architecture as `juliaup` spells it in a full version string, keyed by (os, arch).
const PLATFORM_SUFFIXES = Dict((:linux, :x86_64) => "x64.linux.gnu",
                               (:linux, :i686) => "x86.linux.gnu",
                               (:linux, :aarch64) => "aarch64.linux.gnu",
                               (:macos, :x86_64) => "x64.apple.darwin14",
                               (:macos, :aarch64) => "aarch64.apple.darwin14",
                               (:windows, :x86_64) => "x64.w64.mingw32",
                               (:windows, :i686) => "x86.w64.mingw32",
                               (:freebsd, :x86_64) => "x64.unknown.freebsd11.1")

# Which client databases a build must be written into. A client lists every architecture it can
# execute, mirroring `compatible_archs` in juliaup: 64 bit hosts run 32 bit builds, and Apple
# Silicon runs x86_64 builds through Rosetta 2.
const TARGET_MAP = Dict((:linux, :x86_64) => ["x86_64-unknown-linux-gnu",
                                              "x86_64-unknown-linux-musl"],
                        (:linux, :i686) => ["i686-unknown-linux-gnu",
                                            "i686-unknown-linux-musl",
                                            "x86_64-unknown-linux-gnu",
                                            "x86_64-unknown-linux-musl"],
                        (:linux, :aarch64) => ["aarch64-unknown-linux-gnu",
                                               "aarch64-unknown-linux-musl"],
                        (:macos, :x86_64) => ["x86_64-apple-darwin",
                                              "aarch64-apple-darwin"],
                        (:macos, :aarch64) => ["aarch64-apple-darwin"],
                        (:windows, :x86_64) => ["x86_64-pc-windows-gnu",
                                                "x86_64-pc-windows-msvc"],
                        (:windows, :i686) => ["i686-pc-windows-gnu",
                                              "i686-pc-windows-msvc",
                                              "x86_64-pc-windows-gnu",
                                              "x86_64-pc-windows-msvc"],
                        (:freebsd, :x86_64) => ["x86_64-unknown-freebsd"])

"""
    VersionDB(versions, channels, dbversion)

In-memory form of a `juliaup` version database.

- `versions` maps a full version string such as `"1.12.7+0.x64.linux.gnu"` to the `UrlPath` of the
  distribution tarball. The path is resolved against the server base, so a relative value keeps the
  database portable across hosts while an absolute URL points at another host entirely.
- `channels` maps a channel name such as `"release"` to a key of `versions`.
- `dbversion` is the number published in the `*DBVERSION` pointer files.
"""
struct VersionDB
    versions::Dict{String, String}
    channels::Dict{String, String}
    dbversion::VersionNumber
end

VersionDB(dbversion::VersionNumber) = VersionDB(Dict{String, String}(), Dict{String, String}(), dbversion)

Base.copy(db::VersionDB) = VersionDB(copy(db.versions), copy(db.channels), db.dbversion)

"""
    platform_suffix(os::Symbol, arch::Symbol) -> String

Return the `<arch>.<vendor>.<os>` tail `juliaup` expects in a full version string.
"""
function platform_suffix(os::Symbol, arch::Symbol)

    suffix = get(PLATFORM_SUFFIXES, (os, arch), nothing)

    if isnothing(suffix)
        error("No juliaup platform is defined for $os/$arch. Supported combinations are: " *
              join(("$o/$a" for (o, a) in sort(collect(keys(PLATFORM_SUFFIXES)))), ", "))
    end

    return suffix
end

"""
    targets_for(os::Symbol, arch::Symbol) -> Vector{String}

Return the client databases a build for `os`/`arch` must be written into.
"""
function targets_for(os::Symbol, arch::Symbol)

    targets = get(TARGET_MAP, (os, arch), nothing)

    if isnothing(targets)
        error("No juliaup targets are defined for $os/$arch. Supported combinations are: " *
              join(("$o/$a" for (o, a) in sort(collect(keys(TARGET_MAP)))), ", "))
    end

    return copy(targets)
end

"""
    sanitize_build_tag(tag::AbstractString) -> String

Replace `.` with `x` in a build tag so it survives `juliaup`'s parsing.

`juliaup` splits the build metadata of a full version string on `.` and reads the second component
as the architecture. A tag carrying dots shifts that index, and the entry silently resolves to a
nonsense architecture. JuliaHub hit this with early Dyad releases — `1.11.8+dyad-2.1.0-rc3.x64.linux.gnu`
parses its architecture as `"1"` — and their later entries read `dyad-2x1x0-rc3` instead.
"""
function sanitize_build_tag(tag::AbstractString)

    isempty(tag) && error("The build tag must not be empty")

    sanitized = replace(tag, '.' => 'x')

    if !occursin(r"^[A-Za-z0-9\-]+$", sanitized)
        error("The build tag `$tag` is not a valid semantic version build identifier. Only " *
              "alphanumeric characters, `-` and `.` are allowed.")
    end

    return sanitized
end

"""
    full_version_string(julia_version, build_tag, os, arch) -> String

Build the key `juliaup` uses to identify an installable version, for instance
`"1.12.7+myapp-1x2x0.x64.linux.gnu"`. The build tag is sanitized with [`sanitize_build_tag`](@ref).
"""
function full_version_string(julia_version::VersionNumber, build_tag::AbstractString, os::Symbol, arch::Symbol)

    version = VersionNumber(julia_version.major, julia_version.minor, julia_version.patch)

    return "$version+$(sanitize_build_tag(build_tag)).$(platform_suffix(os, arch))"
end

"""
    read_versiondb(path::String) -> VersionDB

Parse a `juliaup` version database. The nested JSON objects are flattened into plain `Dict`s so
the representation does not depend on the JSON implementation.
"""
function read_versiondb(path::String)

    parsed = JSON.parsefile(path)

    versions = Dict{String, String}(key => value["UrlPath"]
                                    for (key, value) in parsed["AvailableVersions"])

    channels = Dict{String, String}(key => value["Version"]
                                    for (key, value) in parsed["AvailableChannels"])

    return VersionDB(versions, channels, VersionNumber(parsed["Version"]))
end

"""
    write_versiondb(path::String, db::VersionDB)

Serialize `db` into the shape `juliaup` deserializes. Keys are sorted so republishing an unchanged
database produces an unchanged file.
"""
function write_versiondb(path::String, db::VersionDB)

    mkpath(dirname(path))

    document = Dict("AvailableVersions" => Dict(key => Dict("UrlPath" => db.versions[key])
                                                for key in sort(collect(keys(db.versions)))),
                    "AvailableChannels" => Dict(key => Dict("Version" => db.channels[key])
                                                for key in sort(collect(keys(db.channels)))),
                    "Version" => string(db.dbversion))

    open(path, "w") do file
        write(file, JSON.json(document))
    end

    return
end

"""
    add_version!(db::VersionDB, fullversion::String, urlpath::String)

Register an installable version. `urlpath` is resolved against the server base, so pass a relative
path when the tarballs are served from the same host and an absolute URL otherwise.
"""
function add_version!(db::VersionDB, fullversion::AbstractString, urlpath::AbstractString)
    db.versions[fullversion] = urlpath
    return db
end

"""
    add_channel!(db::VersionDB, channel::String, fullversion::String)

Point `channel` at an already registered version. A channel referring to an unknown version would
leave `juliaup` reporting a missing download url only once a user tries to install it.
"""
function add_channel!(db::VersionDB, channel::AbstractString, fullversion::AbstractString)

    if !haskey(db.versions, fullversion)
        error("Can not add channel `$channel`: version `$fullversion` is not in the database. " *
              "Register it with `add_version!` first.")
    end

    db.channels[channel] = fullversion

    return db
end

"""
    merge(base::VersionDB, overlay::VersionDB) -> VersionDB

Combine two databases, with `overlay` winning on conflicts and providing the resulting database
version. This is how a mirror keeps the stock channels working while adding its own.
"""
function Base.merge(base::VersionDB, overlay::VersionDB)
    return VersionDB(merge(base.versions, overlay.versions),
                     merge(base.channels, overlay.channels),
                     overlay.dbversion)
end

"""
    next_dbversion(upstream::VersionNumber, published::VersionNumber = upstream) -> VersionNumber

Return a database version greater than both `upstream` and whatever was `published` previously.

`juliaup` replaces its cached database only when the number it reads exceeds both the number
compiled into its own binary and its local copy, and it logs nothing when it does not. Publishing
at or below the public number therefore makes a distribution invisible with no diagnostic at all.
"""
function next_dbversion(upstream::VersionNumber, published::VersionNumber = upstream)

    highest = max(upstream, published)

    return VersionNumber(highest.major, highest.minor, highest.patch + 1)
end

"""
    fetch_dbversion(; server = DEFAULT_SERVER, channel = :release) -> VersionNumber

Download the database version a server currently advertises for `channel`, which is one of
`:release`, `:releasepreview` or `:dev`.
"""
function fetch_dbversion(; server::AbstractString = DEFAULT_SERVER, channel::Symbol = :release)

    name = channel === :release ? "RELEASECHANNELDBVERSION" :
           channel === :releasepreview ? "RELEASEPREVIEWCHANNELDBVERSION" :
           channel === :dev ? "DEVCHANNELDBVERSION" :
           error("Unknown juliaup channel `$channel`. Expected :release, :releasepreview or :dev.")

    destination = tempname()

    Downloads.download(rstrip(server, '/') * "/juliaup/" * name, destination)

    return VersionNumber(strip(read(destination, String)))
end

"""
    fetch_versiondb(target::String; server = DEFAULT_SERVER, dbversion) -> VersionDB

Download the version database a `juliaup` client with the given target triple would read.
"""
function fetch_versiondb(target::AbstractString;
                         server::AbstractString = DEFAULT_SERVER,
                         dbversion::VersionNumber = fetch_dbversion(; server))

    target in JULIAUP_TARGETS || error("`$target` is not a juliaup target triple")

    url = rstrip(server, '/') * "/juliaup/versiondb/versiondb-$dbversion-$target.json"
    destination = tempname()

    Downloads.download(url, destination)

    return read_versiondb(destination)
end

"""
    fetch_upstream(; server = DEFAULT_SERVER, dbversion) -> Dict{String, VersionDB}

Download the version database for every target triple, keyed by triple. This is the base a mirror
merges its own channels into.
"""
function fetch_upstream(; server::AbstractString = DEFAULT_SERVER,
                        dbversion::VersionNumber = fetch_dbversion(; server))

    @info "Fetching upstream juliaup databases at $dbversion from $server"

    return Dict{String, VersionDB}(target => fetch_versiondb(target; server, dbversion)
                                   for target in JULIAUP_TARGETS)
end
