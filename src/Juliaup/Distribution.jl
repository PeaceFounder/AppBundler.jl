"""
    JuliaupDistribution([overlay]; channel, julia_version, build_tag, kwargs...)

Description of a Julia distribution published through `juliaup`.

Users install it by pointing `JULIAUP_SERVER` at `server` and running `juliaup add <channel>`.
The wrappers produced by [`install_wrappers`](@ref) set that variable for them and isolate the
depot so a stock `juliaup` installation is left untouched.

When `overlay` is provided, application parameters (`APP_NAME`, `APP_VERSION`, ...) are read from
`overlay/Project.toml` and defaults from `overlay/LocalPreferences.toml`, exactly as for the
[`DMG`](@ref), [`MSIX`](@ref) and [`Snap`](@ref) formats.

# Keyword Arguments
- `channel`: Channel name users pass to `juliaup add`, e.g. `"myapp-1.2.0"`
- `julia_version`: Julia version the distribution is built on, taken from the bundled runtime
- `build_tag`: Build identifier embedded in the full version string; sanitized with
  [`sanitize_build_tag`](@ref)
- `server`: HTTPS base url the database is published under, used by the client wrappers
- `asset_base`: Base path or url the tarballs are served from. A relative value keeps the database
  portable across hosts, an absolute url points at another host such as GitHub releases
- `mirror = true`: Merge the upstream database in so the stock channels keep working
- `dbversion = nothing`: Database version to publish; resolved above upstream at publish time when
  left unset
- `depot`: Directory under `~/.julia/juliaup-depots` the wrappers isolate the installation into;
  defaults to the server host
- `upstream_server = DEFAULT_SERVER`: Server to mirror from
"""
struct JuliaupDistribution
    channel::String
    julia_version::VersionNumber
    build_tag::String
    server::String
    asset_base::String
    mirror::Bool
    dbversion::Union{VersionNumber, Nothing}
    depot::String
    upstream_server::String
    parameters::Dict{String, Any}
end

function JuliaupDistribution(;
                             channel::AbstractString,
                             julia_version::VersionNumber,
                             build_tag::AbstractString,
                             app_name::AbstractString,
                             app_version::AbstractString,
                             server::AbstractString = "",
                             asset_base::AbstractString = "assets",
                             mirror::Bool = true,
                             dbversion::Union{VersionNumber, Nothing} = nothing,
                             depot::AbstractString = default_depot(server),
                             upstream_server::AbstractString = DEFAULT_SERVER,
                             parameters::Dict{String, Any} = Dict{String, Any}())

    validate_server(server)
    sanitize_build_tag(build_tag) # fail here rather than on every user's machine

    parameters = copy(parameters)
    parameters["APP_NAME"] = app_name
    parameters["APP_VERSION"] = app_version
    parameters["JULIAUP_CHANNEL"] = channel
    parameters["JULIAUP_SERVER"] = server
    parameters["JULIAUP_DEPOT"] = depot

    return JuliaupDistribution(channel, julia_version, build_tag, server, asset_base,
                               mirror, dbversion, depot, upstream_server, parameters)
end

function JuliaupDistribution(overlay::AbstractString; preferences = AppBundler.preferences(), kwargs...)

    parameters = AppBundler.get_bundle_parameters!(Dict{String, Any}(),
                                                   joinpath(overlay, "Project.toml"); preferences)

    app_name = parameters["APP_NAME"]
    app_version = parameters["APP_VERSION"]

    defaults = (channel = get(preferences, "juliaup_channel", "$app_name-$app_version"),
                julia_version = JuliaImg.get_julia_version(overlay),
                build_tag = "$app_name-$app_version",
                server = get(preferences, "juliaup_server", ""),
                asset_base = get(preferences, "juliaup_asset_base", "assets"),
                mirror = get(preferences, "juliaup_mirror", true),
                upstream_server = get(preferences, "juliaup_upstream_server", DEFAULT_SERVER))

    return JuliaupDistribution(; defaults..., app_name, app_version, parameters, kwargs...)
end

"""
    validate_server(server::AbstractString)

Reject a server url `juliaup` would refuse. It requires HTTPS except on loopback, and rather than
let every user discover that, fail while publishing.
"""
function validate_server(server::AbstractString)

    isempty(server) && return

    scheme, rest = if startswith(server, "https://")
        ("https", server[9:end])
    elseif startswith(server, "http://")
        ("http", server[8:end])
    else
        error("The juliaup server `$server` must be an http(s) url")
    end

    host = first(split(first(split(rest, '/')), ':'))

    if scheme == "http" && !(host in ["localhost", "127.0.0.1", "::1", "[::1]"])
        error("juliaup refuses a plain HTTP server unless it is loopback. Publish `$server` " *
              "over HTTPS instead.")
    end

    return
end

"""
    default_depot(server::AbstractString) -> String

Directory name under `~/.julia/juliaup-depots` to isolate a distribution into, derived from the
server host so distributions from different vendors do not collide.
"""
function default_depot(server::AbstractString)

    isempty(server) && return "appbundler"

    rest = replace(server, r"^https?://" => "")
    host = first(split(first(split(rest, '/')), ':'))

    return isempty(host) ? "appbundler" : String(host)
end

"""
    target_platform(target::AbstractString) -> Tuple{Symbol, Symbol}

Return the `(os, arch)` a `juliaup` client with this target triple runs natively.
"""
function target_platform(target::AbstractString)

    arch = startswith(target, "x86_64") ? :x86_64 :
           startswith(target, "i686") ? :i686 :
           startswith(target, "aarch64") ? :aarch64 :
           error("Can not determine the architecture of juliaup target `$target`")

    os = occursin("linux", target) ? :linux :
         occursin("darwin", target) ? :macos :
         occursin("windows", target) ? :windows :
         occursin("freebsd", target) ? :freebsd :
         error("Can not determine the operating system of juliaup target `$target`")

    return (os, arch)
end

"""
    asset_url(dist::JuliaupDistribution, os::Symbol, arch::Symbol) -> String

Url of the tarball for one platform, following the naming the tarball bundle target produces:
`<app-name>-<app-version>-<os>-<arch>.tar.gz`.
"""
function asset_url(dist::JuliaupDistribution, os::Symbol, arch::Symbol)

    name = "$(dist.parameters["APP_NAME"])-$(dist.parameters["APP_VERSION"])-$os-$arch.tar.gz"

    return isempty(dist.asset_base) ? name : rstrip(dist.asset_base, '/') * "/" * name
end

"""
    publish(dist::JuliaupDistribution, site::String; assets, upstream = nothing, dbversion = nothing)

Write the static file tree a `juliaup` client reads into `site`.

`assets` lists the platforms that were built, either as `(os, arch)` tuples — whose tarball urls are
then derived from `dist.asset_base` — or as `(os, arch) => url` pairs when the urls are known.

The resulting tree can be served by any static host:

```
<site>/juliaup/DBVERSION
<site>/juliaup/RELEASECHANNELDBVERSION
<site>/juliaup/RELEASEPREVIEWCHANNELDBVERSION
<site>/juliaup/DEVCHANNELDBVERSION
<site>/juliaup/versiondb/versiondb-<dbversion>-<target>.json   (one per target triple)
```

All four pointer files carry the same number. `juliaup` reads only the one matching the channel it
was installed from, and a client on `dev` or `releasepreview` would otherwise take a 404 on a
database that was never written.
"""
function publish(dist::JuliaupDistribution, site::String;
                 assets,
                 upstream::Union{Dict{String, VersionDB}, Nothing} = nothing,
                 dbversion::Union{VersionNumber, Nothing} = dist.dbversion)

    platforms = normalize_assets(dist, assets)

    isempty(platforms) && error("No assets were given to publish. Pass at least one (os, arch).")

    if isnothing(upstream) && dist.mirror
        upstream = fetch_upstream(; server = dist.upstream_server)
    end

    if isnothing(dbversion)
        upstream_version = isnothing(upstream) ? fetch_dbversion(; server = dist.upstream_server) :
            maximum(db.dbversion for db in values(upstream))
        dbversion = next_dbversion(upstream_version, published_dbversion(site, upstream_version))
    end

    juliaup_dir = joinpath(site, "juliaup")
    mkpath(joinpath(juliaup_dir, "versiondb"))

    for target in JULIAUP_TARGETS

        base = isnothing(upstream) ? VersionDB(dbversion) : copy(upstream[target])
        db = VersionDB(base.versions, base.channels, dbversion)

        register!(db, dist, target, platforms)

        write_versiondb(joinpath(juliaup_dir, "versiondb", "versiondb-$dbversion-$target.json"), db)
    end

    for name in DBVERSION_FILES
        write(joinpath(juliaup_dir, name), "$dbversion\n")
    end

    @info "Published juliaup channel `$(dist.channel)` at database version $dbversion into $site"

    return dbversion
end

function normalize_assets(dist::JuliaupDistribution, assets)

    platforms = Pair{Tuple{Symbol, Symbol}, String}[]

    for entry in assets
        if entry isa Pair
            os, arch = entry.first
            push!(platforms, (os, arch) => String(entry.second))
        else
            os, arch = entry
            push!(platforms, (os, arch) => asset_url(dist, os, arch))
        end
    end

    return platforms
end

"""
    register!(db, dist, target, platforms)

Add the distribution's versions and channels to one target's database.

Every platform the target can execute is registered under a `<channel>~<arch>` alias, following the
convention upstream uses. The bare channel resolves to the target's native architecture when it was
built, and otherwise to the first compatible build — which is how an Apple Silicon client falls back
to an x86_64 distribution through Rosetta 2.
"""
function register!(db::VersionDB, dist::JuliaupDistribution, target::AbstractString, platforms)

    compatible = [platform for platform in platforms if target in targets_for(platform.first...)]

    isempty(compatible) && return db

    native = target_platform(target)
    preferred = something(findfirst(platform -> platform.first == native, compatible), 1)

    for (index, ((os, arch), url)) in enumerate(compatible)

        fullversion = full_version_string(dist.julia_version, dist.build_tag, os, arch)

        add_version!(db, fullversion, url)
        add_channel!(db, "$(dist.channel)~$(juliaup_arch(os, arch))", fullversion)

        if index == preferred
            add_channel!(db, dist.channel, fullversion)
        end
    end

    return db
end

"""
    juliaup_arch(os::Symbol, arch::Symbol) -> String

Architecture token `juliaup` uses in channel aliases and version strings: `x64`, `x86` or `aarch64`.
"""
juliaup_arch(os::Symbol, arch::Symbol) = String(first(split(platform_suffix(os, arch), '.')))

"""
    published_dbversion(site::String, fallback::VersionNumber) -> VersionNumber

Read back the database version a site already advertises, so republishing keeps climbing rather
than reusing a number clients have already cached.
"""
function published_dbversion(site::String, fallback::VersionNumber)

    path = joinpath(site, "juliaup", "RELEASECHANNELDBVERSION")

    isfile(path) || return fallback

    return try
        VersionNumber(strip(read(path, String)))
    catch
        fallback
    end
end

"""
    install_wrappers(dist::JuliaupDistribution, destination::String)

Write the client wrappers into `destination`: `<app>-juliaup` and `<app>-julia`, plus PowerShell
equivalents for Windows.

They export `JULIAUP_SERVER` and `JULIAUP_DEPOT_PATH` before delegating to the real binaries, so a
user's stock `juliaup` installation and its channels are left alone. This mirrors how the Dyad
distribution is shipped.
"""
function install_wrappers(dist::JuliaupDistribution, destination::String;
                          prefix = joinpath(dirname(dirname(@__DIR__)), "recipes"))

    isempty(dist.server) && error("A juliaup `server` must be configured before client wrappers " *
                                  "can be written, otherwise they point nowhere.")

    mkpath(destination)

    app_name = dist.parameters["APP_NAME"]

    for (source, target, executable) in [("juliaup/juliaup.sh", "$app_name-juliaup", true),
                                         ("juliaup/julia.sh", "$app_name-julia", true),
                                         ("juliaup/juliaup.ps1", "$app_name-juliaup.ps1", false),
                                         ("juliaup/julia.ps1", "$app_name-julia.ps1", false)]

        AppBundler.install(joinpath(prefix, source), joinpath(destination, target);
                           parameters = dist.parameters, executable, force = true)
    end

    return
end
