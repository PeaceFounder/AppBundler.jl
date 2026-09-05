import AppBundler
import AppBundler.Juliaup
import AppBundler.Juliaup: VersionDB, JULIAUP_TARGETS, DBVERSION_FILES

using Test

const FIXTURE = joinpath(@__DIR__, "fixtures", "versiondb-1.0.92-x86_64-unknown-linux-gnu.json")

@testset "Build tag sanitization" begin

    # `juliaup` splits the build metadata on "." and reads the second component as the
    # architecture. A tag carrying dots shifts that index and the entry resolves to a
    # bogus architecture, which is why JuliaHub moved from `dyad-2.1.0-rc3` to `dyad-2x1x0-rc3`.
    @test Juliaup.sanitize_build_tag("2.1.0-rc3") == "2x1x0-rc3"
    @test Juliaup.sanitize_build_tag("dyad-3.3.0") == "dyad-3x3x0"
    @test Juliaup.sanitize_build_tag("3.2.0-next.87") == "3x2x0-nextx87"
    @test Juliaup.sanitize_build_tag("0") == "0"

    @test_throws ErrorException Juliaup.sanitize_build_tag("")
    @test_throws ErrorException Juliaup.sanitize_build_tag("has space")
end

@testset "Full version strings" begin

    @test Juliaup.platform_suffix(:linux, :x86_64) == "x64.linux.gnu"
    @test Juliaup.platform_suffix(:linux, :i686) == "x86.linux.gnu"
    @test Juliaup.platform_suffix(:linux, :aarch64) == "aarch64.linux.gnu"
    @test Juliaup.platform_suffix(:macos, :x86_64) == "x64.apple.darwin14"
    @test Juliaup.platform_suffix(:macos, :aarch64) == "aarch64.apple.darwin14"
    @test Juliaup.platform_suffix(:windows, :x86_64) == "x64.w64.mingw32"
    @test Juliaup.platform_suffix(:windows, :i686) == "x86.w64.mingw32"
    @test Juliaup.platform_suffix(:freebsd, :x86_64) == "x64.unknown.freebsd11.1"

    @test_throws ErrorException Juliaup.platform_suffix(:macos, :i686)
    @test_throws ErrorException Juliaup.platform_suffix(:haiku, :x86_64)

    # Matches the shape of upstream entries such as `1.12.7+0.x64.linux.gnu`
    @test Juliaup.full_version_string(v"1.12.7", "0", :linux, :x86_64) == "1.12.7+0.x64.linux.gnu"

    # Build tags are sanitized on the way in so callers cannot construct a broken entry
    @test Juliaup.full_version_string(v"1.12.7", "myapp-1.2.0", :linux, :x86_64) ==
        "1.12.7+myapp-1x2x0.x64.linux.gnu"

    # The architecture must survive `juliaup`'s own parsing: build metadata split on ".",
    # second component is the architecture.
    for (os, arch, expected) in [(:linux, :x86_64, "x64"), (:macos, :aarch64, "aarch64"),
                                 (:windows, :i686, "x86")]
        parts = split(split(Juliaup.full_version_string(v"1.11.9", "app-2.0.0", os, arch), '+')[2], '.')
        @test length(parts) >= 4
        @test parts[2] == expected
    end
end

@testset "Target triples" begin

    @test length(JULIAUP_TARGETS) == 13
    @test allunique(JULIAUP_TARGETS)
    @test "x86_64-unknown-linux-gnu" in JULIAUP_TARGETS
    @test "x86_64-unknown-linux-musl" in JULIAUP_TARGETS
    @test "aarch64-apple-darwin" in JULIAUP_TARGETS
    @test "x86_64-unknown-freebsd" in JULIAUP_TARGETS

    # The triple describes the juliaup client binary, not the Julia build. The Linux client
    # is musl-static but runs on glibc hosts, so a Linux build must land in both databases.
    @test Set(Juliaup.targets_for(:linux, :x86_64)) ==
        Set(["x86_64-unknown-linux-gnu", "x86_64-unknown-linux-musl"])

    # A 32 bit build is also reachable from a 64 bit client
    @test "x86_64-unknown-linux-gnu" in Juliaup.targets_for(:linux, :i686)
    @test "i686-unknown-linux-gnu" in Juliaup.targets_for(:linux, :i686)
    @test "i686-unknown-linux-gnu" ∉ Juliaup.targets_for(:linux, :x86_64)

    # Rosetta 2: an x86_64 macOS build is installable from an Apple Silicon client
    @test Set(Juliaup.targets_for(:macos, :x86_64)) ==
        Set(["x86_64-apple-darwin", "aarch64-apple-darwin"])
    @test Juliaup.targets_for(:macos, :aarch64) == ["aarch64-apple-darwin"]

    @test Set(Juliaup.targets_for(:windows, :x86_64)) ==
        Set(["x86_64-pc-windows-gnu", "x86_64-pc-windows-msvc"])

    @test Juliaup.targets_for(:freebsd, :x86_64) == ["x86_64-unknown-freebsd"]

    # Every target a build maps to must be one juliaup actually asks for
    for os in [:linux, :macos, :windows, :freebsd], arch in [:x86_64, :i686, :aarch64]
        targets = try
            Juliaup.targets_for(os, arch)
        catch
            continue
        end
        @test all(in(JULIAUP_TARGETS), targets)
    end
end

@testset "Version database round trip" begin

    db = Juliaup.read_versiondb(FIXTURE)

    @test db.dbversion == v"1.0.92"
    @test db.channels["release"] == "1.12.7+0.x64.linux.gnu"
    @test db.versions["1.12.7+0.x64.linux.gnu"] == "bin/linux/x64/1.12/julia-1.12.7-linux-x86_64.tar.gz"
    @test length(db.versions) == 4
    @test length(db.channels) == 10

    # Internals are plain Dicts so the JSON implementation does not leak into the API
    @test db.versions isa Dict{String, String}
    @test db.channels isa Dict{String, String}

    path = joinpath(mktempdir(), "versiondb.json")
    Juliaup.write_versiondb(path, db)
    reread = Juliaup.read_versiondb(path)

    @test reread.versions == db.versions
    @test reread.channels == db.channels
    @test reread.dbversion == db.dbversion

    # The serialized form must match what juliaup deserializes into
    raw = read(path, String)
    @test occursin("\"AvailableVersions\"", raw)
    @test occursin("\"AvailableChannels\"", raw)
    @test occursin("\"UrlPath\"", raw)
    @test occursin("\"Version\"", raw)
end

@testset "Adding versions and channels" begin

    db = Juliaup.read_versiondb(FIXTURE)
    fullversion = Juliaup.full_version_string(v"1.12.7", "myapp-1.2.0", :linux, :x86_64)

    Juliaup.add_version!(db, fullversion, "https://example.com/myapp-1.2.0-linux-x86_64.tar.gz")
    Juliaup.add_channel!(db, "myapp-1.2.0", fullversion)

    @test db.versions[fullversion] == "https://example.com/myapp-1.2.0-linux-x86_64.tar.gz"
    @test db.channels["myapp-1.2.0"] == fullversion

    # Upstream entries are untouched — this is the mirroring property that keeps
    # `juliaup add release` working against a custom server.
    @test db.channels["release"] == "1.12.7+0.x64.linux.gnu"
    @test length(db.versions) == 5

    # A channel may only point at a version the database knows about
    @test_throws ErrorException Juliaup.add_channel!(db, "dangling", "9.9.9+0.x64.linux.gnu")
end

@testset "Database merging" begin

    base = Juliaup.read_versiondb(FIXTURE)

    overlay = VersionDB(Dict("1.12.7+app.x64.linux.gnu" => "assets/app.tar.gz"),
                        Dict("app" => "1.12.7+app.x64.linux.gnu"),
                        v"1.0.100")

    merged = merge(base, overlay)

    @test length(merged.versions) == 5
    @test merged.channels["app"] == "1.12.7+app.x64.linux.gnu"
    @test merged.channels["release"] == "1.12.7+0.x64.linux.gnu"

    # The overlay wins on conflicts and carries the resulting database version
    @test merged.dbversion == v"1.0.100"

    conflicting = VersionDB(Dict{String, String}(),
                            Dict("release" => "1.10.12+0.x64.linux.gnu"),
                            v"1.0.100")
    @test merge(base, conflicting).channels["release"] == "1.10.12+0.x64.linux.gnu"

    # Merging leaves the operands alone
    @test length(base.versions) == 4
    @test base.channels["release"] == "1.12.7+0.x64.linux.gnu"
end

@testset "Database version bumping" begin

    # juliaup ignores a published database whose number is not greater than the one compiled
    # into the binary, and reports nothing when it does. Publishing must always go above upstream.
    @test Juliaup.next_dbversion(v"1.0.92") > v"1.0.92"
    @test Juliaup.next_dbversion(v"1.0.92") == v"1.0.93"
    @test Juliaup.next_dbversion(v"1.0.92", v"1.0.124") == v"1.0.125"
    @test Juliaup.next_dbversion(v"1.0.130", v"1.0.124") == v"1.0.131"

    # Same major/minor line as upstream, otherwise the semver comparison stops being meaningful
    @test Juliaup.next_dbversion(v"1.0.92").major == 1
    @test Juliaup.next_dbversion(v"1.0.92").minor == 0
end

@testset "Publishing a distribution" begin

    site = mktempdir()

    dist = Juliaup.JuliaupDistribution(;
        channel = "myapp-1.2.0",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        asset_base = "https://github.com/acme/myapp/releases/download/v1.2.0",
        app_name = "myapp",
        app_version = "1.2.0",
        mirror = false,
        dbversion = v"1.0.200")

    Juliaup.publish(dist, site; assets = [(:linux, :x86_64), (:macos, :aarch64)])

    # All four pointer files, all carrying the same number: juliaup's `dev` and
    # `releasepreview` clients read their own file and 404 on a database we never wrote.
    for name in DBVERSION_FILES
        path = joinpath(site, "juliaup", name)
        @test isfile(path)
        @test strip(read(path, String)) == "1.0.200"
    end
    @test length(DBVERSION_FILES) == 4

    # One database per target triple, and nothing else
    dbdir = joinpath(site, "juliaup", "versiondb")
    written = readdir(dbdir)
    @test length(written) == 13
    for target in JULIAUP_TARGETS
        @test "versiondb-1.0.200-$target.json" in written
    end

    linux = Juliaup.read_versiondb(joinpath(dbdir, "versiondb-1.0.200-x86_64-unknown-linux-gnu.json"))
    @test linux.dbversion == v"1.0.200"
    @test haskey(linux.channels, "myapp-1.2.0")

    fullversion = linux.channels["myapp-1.2.0"]
    @test fullversion == "1.12.7+myapp-1x2x0.x64.linux.gnu"
    @test linux.versions[fullversion] ==
        "https://github.com/acme/myapp/releases/download/v1.2.0/myapp-1.2.0-linux-x86_64.tar.gz"

    # An architecture alias, as upstream publishes alongside every channel
    @test linux.channels["myapp-1.2.0~x64"] == fullversion

    # The musl database is the one a stock Linux juliaup actually reads
    musl = Juliaup.read_versiondb(joinpath(dbdir, "versiondb-1.0.200-x86_64-unknown-linux-musl.json"))
    @test musl.channels == linux.channels
    @test musl.versions == linux.versions

    # macOS aarch64 lands only in the Apple Silicon database
    darwin = Juliaup.read_versiondb(joinpath(dbdir, "versiondb-1.0.200-aarch64-apple-darwin.json"))
    @test darwin.channels["myapp-1.2.0"] == "1.12.7+myapp-1x2x0.aarch64.apple.darwin14"
    @test darwin.versions["1.12.7+myapp-1x2x0.aarch64.apple.darwin14"] ==
        "https://github.com/acme/myapp/releases/download/v1.2.0/myapp-1.2.0-macos-aarch64.tar.gz"

    intel = Juliaup.read_versiondb(joinpath(dbdir, "versiondb-1.0.200-x86_64-apple-darwin.json"))
    @test !haskey(intel.channels, "myapp-1.2.0")

    # Standalone mode carries our channels only
    @test !haskey(linux.channels, "release")
    @test length(linux.versions) == 1
end

@testset "Publishing on top of a mirrored database" begin

    site = mktempdir()

    dist = Juliaup.JuliaupDistribution(;
        channel = "myapp",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        asset_base = "https://example.com/assets",
        app_name = "myapp",
        app_version = "1.2.0",
        mirror = false,
        dbversion = v"1.0.200")

    upstream = Dict(target => Juliaup.read_versiondb(FIXTURE) for target in JULIAUP_TARGETS)

    Juliaup.publish(dist, site; assets = [(:linux, :x86_64)], upstream)

    db = Juliaup.read_versiondb(joinpath(site, "juliaup", "versiondb",
                                         "versiondb-1.0.200-x86_64-unknown-linux-gnu.json"))

    # Stock channels keep working next to ours — the whole point of mirroring
    @test db.channels["release"] == "1.12.7+0.x64.linux.gnu"
    @test db.channels["lts"] == "1.10.12+0.x64.linux.gnu"
    @test db.channels["myapp"] == "1.12.7+myapp-1x2x0.x64.linux.gnu"
    @test length(db.versions) == 5
    @test db.dbversion == v"1.0.200"
end

@testset "Relative asset paths" begin

    site = mktempdir()

    # A site that also serves the tarballs keeps UrlPath relative, so the mirror can be
    # moved to another host without rewriting the database (this is what JuliaHub does).
    dist = Juliaup.JuliaupDistribution(;
        channel = "myapp",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        asset_base = "assets",
        app_name = "myapp",
        app_version = "1.2.0",
        mirror = false,
        dbversion = v"1.0.200")

    Juliaup.publish(dist, site; assets = [(:linux, :x86_64)])

    db = Juliaup.read_versiondb(joinpath(site, "juliaup", "versiondb",
                                         "versiondb-1.0.200-x86_64-unknown-linux-gnu.json"))

    @test db.versions["1.12.7+myapp-1x2x0.x64.linux.gnu"] ==
        "assets/myapp-1.2.0-linux-x86_64.tar.gz"
end

@testset "Client wrappers" begin

    destination = mktempdir()

    dist = Juliaup.JuliaupDistribution(;
        channel = "myapp",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        server = "https://acme.github.io/myapp",
        asset_base = "assets",
        app_name = "myapp",
        app_version = "1.2.0")

    Juliaup.install_wrappers(dist, destination)

    for name in ["myapp-juliaup", "myapp-julia", "myapp-juliaup.ps1", "myapp-julia.ps1"]
        @test isfile(joinpath(destination, name))
    end

    juliaup = read(joinpath(destination, "myapp-juliaup"), String)

    @test occursin("https://acme.github.io/myapp", juliaup)
    @test occursin("JULIAUP_SERVER", juliaup)

    # The depot is isolated so the user's stock juliaup installation is left alone
    @test occursin("JULIAUP_DEPOT_PATH", juliaup)
    @test occursin("juliaup-depots", juliaup)

    if Sys.isunix()
        @test (stat(joinpath(destination, "myapp-juliaup")).mode & 0o111) != 0
    end

    powershell = read(joinpath(destination, "myapp-juliaup.ps1"), String)
    @test occursin("JULIAUP_SERVER", powershell)
    @test occursin("https://acme.github.io/myapp", powershell)
end

@testset "Server URL validation" begin

    # juliaup refuses a non-HTTPS server unless it is loopback, so a bad value should fail
    # at publish time rather than silently on every user's machine.
    @test_throws ErrorException Juliaup.JuliaupDistribution(;
        channel = "myapp",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        server = "http://example.com",
        asset_base = "assets",
        app_name = "myapp",
        app_version = "1.2.0")

    # Loopback over plain HTTP is explicitly allowed by juliaup and is what the end to end
    # test relies on
    @test Juliaup.JuliaupDistribution(;
        channel = "myapp",
        julia_version = v"1.12.7",
        build_tag = "myapp-1.2.0",
        server = "http://127.0.0.1:8080",
        asset_base = "assets",
        app_name = "myapp",
        app_version = "1.2.0") isa Juliaup.JuliaupDistribution
end
