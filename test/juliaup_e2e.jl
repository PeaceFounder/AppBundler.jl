# End to end check of the published layout against a real `juliaup` client.
#
# `juliaup` refuses a non-HTTPS server unless it is loopback, so a plain HTTP server bound to
# 127.0.0.1 is enough to exercise the complete flow it performs for `juliaup add <channel>`:
#
#   GET /juliaup/RELEASECHANNELDBVERSION
#   GET /juliaup/versiondb/versiondb-<dbversion>-<target>.json
#   GET <UrlPath>
#
# Opt in with JULIA_RUN_JULIAUP_E2E=true; skipped when `juliaup` is not on PATH.

import AppBundler
import AppBundler.Juliaup
import AppBundler.TarPack

import Sockets
import Tar
import CodecZlib

using Test

const CONTENT_TYPES = Dict(".json" => "application/json",
                           ".gz" => "application/gzip")

function content_type(path)
    return get(CONTENT_TYPES, last(splitext(path)), "application/octet-stream")
end

"""
    serve(root) -> (port, stop)

Minimal blocking HTTP/1.1 file server over loopback, serving `root`. Returns the bound port and
a function that shuts the server down.
"""
function serve(root)

    server = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(server)[2]

    task = @async begin
        while isopen(server)
            socket = try
                Sockets.accept(server)
            catch err
                err isa Base.IOError || rethrow() # the listener was closed by `stop`
                break
            end

            @async try
                request = readline(socket)
                while !isempty(strip(readline(socket))) end # discard headers

                fields = split(request)
                target = length(fields) > 1 ? fields[2] : "/"
                path = joinpath(root, lstrip(first(split(target, '?')), '/'))

                if isfile(path)
                    body = read(path)
                    write(socket, "HTTP/1.1 200 OK\r\n" *
                          "Content-Type: $(content_type(path))\r\n" *
                          "Content-Length: $(length(body))\r\n" *
                          "Connection: close\r\n\r\n")
                    write(socket, body)
                else
                    write(socket, "HTTP/1.1 404 Not Found\r\n" *
                          "Content-Length: 0\r\nConnection: close\r\n\r\n")
                end
            catch err
                # A client hanging up mid response is not a test failure, but anything else
                # would otherwise be swallowed and surface as an unexplained timeout.
                err isa Base.IOError || @error "Request handler failed" exception = err
            finally
                close(socket)
            end
        end
    end

    return port, () -> (close(server); wait(task))
end

"""
Writes a stub distribution that answers the handful of calls juliaup makes against an
installed Julia, and packs it the way the tarball target would.
"""
function stub_tarball(destination, root_name, version)

    staging = mktempdir()
    root = joinpath(staging, root_name)
    mkpath(joinpath(root, "bin"))
    mkpath(joinpath(root, "lib", "julia"))

    write(joinpath(root, "bin", "julia"), """
    #!/bin/sh
    for arg in "\$@"; do
      case "\$arg" in
        -v|--version) echo "julia version $version"; exit 0 ;;
      esac
    done
    printf '%s' "$version"
    """)
    chmod(joinpath(root, "bin", "julia"), 0o755)

    write(joinpath(root, "lib", "julia", "sys.so"), "stub sysimage")

    TarPack.pack(root, destination)

    return destination
end

"""
The target triple of the local juliaup binary, i.e. the one database it reads. Derived from the
name juliaup gave its own cached copy rather than guessed from the host, since the Linux client is
musl-static and reads the musl database even on a glibc system.
"""
function juliaup_target(depot = joinpath(homedir(), ".julia", "juliaup"))

    for entry in readdir(depot)
        captured = match(r"^versiondb-(.+)\.json$", entry)
        isnothing(captured) || return captured[1]
    end

    error("Could not determine the local juliaup target triple from $depot")
end

"""
Copy of a distribution under a different channel name, so one published site can carry several.
"""
function distribution_for(dist, channel)
    return Juliaup.JuliaupDistribution(; channel,
                                       julia_version = dist.julia_version,
                                       build_tag = dist.build_tag,
                                       server = dist.server,
                                       asset_base = dist.asset_base,
                                       app_name = dist.parameters["APP_NAME"],
                                       app_version = dist.parameters["APP_VERSION"],
                                       mirror = false)
end

if !Sys.isunix()
    @info "Skipping juliaup end to end test: POSIX host required"
elseif isnothing(Sys.which("juliaup"))
    @info "Skipping juliaup end to end test: `juliaup` not found on PATH"
else

    site = mktempdir()
    depot = mktempdir()

    julia_version = v"1.12.7"
    channel = "e2eapp-1.0.0"

    mkpath(joinpath(site, "assets"))

    port, stop = serve(site)
    server = "http://127.0.0.1:$port"

    try
        os = :linux
        arch = Sys.ARCH === :aarch64 ? :aarch64 : :x86_64

        stub_tarball(joinpath(site, "assets", "e2eapp-1.0.0-$os-$arch.tar.gz"),
                     "e2eapp-1.0.0", julia_version)

        dist = Juliaup.JuliaupDistribution(;
            channel,
            julia_version,
            build_tag = "e2eapp-1.0.0",
            server,
            asset_base = "assets",
            app_name = "e2eapp",
            app_version = "1.0.0",
            mirror = false,
            # Has to exceed the number compiled into the juliaup binary, otherwise the
            # database is ignored and nothing at all is reported.
            dbversion = v"99.0.0")

        Juliaup.publish(dist, site; assets = [(os, arch)])

        @testset "juliaup installs the published channel" begin

            env = copy(ENV)
            env["JULIAUP_SERVER"] = server
            env["JULIAUP_DEPOT_PATH"] = depot

            add = run(ignorestatus(setenv(`juliaup add $channel`, env)))
            @test add.exitcode == 0

            installed = joinpath(depot, "juliaup",
                                 "julia-$(Juliaup.full_version_string(julia_version, "e2eapp-1.0.0", os, arch))")
            @test isdir(installed)
            @test isfile(joinpath(installed, "bin", "julia"))

            status = read(setenv(`juliaup status`, env), String)
            @test occursin(channel, status)
        end

        @testset "An absolute UrlPath escapes the server base" begin

            # This is what makes the GitHub Pages layout work: the database is served from
            # Pages while the tarballs stay on the releases page. juliaup resolves UrlPath
            # with `Url::join`, so an absolute url replaces the base entirely and none of the
            # tarball bytes pass through the host serving the database.
            absolute = "$server/assets/e2eapp-1.0.0-$os-$arch.tar.gz"

            elsewhere = distribution_for(dist, "e2eapp-absolute")

            Juliaup.publish(elsewhere, site;
                            assets = [(os, arch) => absolute],
                            dbversion = v"99.0.1")

            db = Juliaup.read_versiondb(joinpath(site, "juliaup", "versiondb",
                                                 "versiondb-99.0.1-$(juliaup_target()).json"))
            @test db.versions[db.channels["e2eapp-absolute"]] == absolute

            env = copy(ENV)
            env["JULIAUP_SERVER"] = server
            env["JULIAUP_DEPOT_PATH"] = depot

            add = run(ignorestatus(setenv(`juliaup add e2eapp-absolute`, env)))
            @test add.exitcode == 0

            status = read(setenv(`juliaup status`, env), String)
            @test occursin("e2eapp-absolute", status)
        end
    finally
        stop()
    end
end
