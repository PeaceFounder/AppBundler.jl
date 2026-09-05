import AppBundler
import AppBundler: Tarball, bundle, stage, TarPack

import Tar
import CodecZlib

using Test

"""
Lists the archive entries the way `juliaup` sees them, i.e. after gzip decompression.
"""
function archive_entries(path)
    entries = Tar.Header[]
    open(path) do io
        Tar.list(CodecZlib.GzipDecompressorStream(io)) do header
            push!(entries, header)
        end
    end
    return entries
end

"""
Writes the shape of a staged Julia distribution, without actually building one.
"""
function fake_distribution(root)
    mkpath(joinpath(root, "bin"))
    mkpath(joinpath(root, "lib", "julia"))
    mkpath(joinpath(root, "share", "julia", "stdlib", "v1.12"))

    write(joinpath(root, "bin", "julia"), "#!/bin/sh\necho fake julia\n")
    Sys.isunix() && chmod(joinpath(root, "bin", "julia"), 0o755)

    write(joinpath(root, "lib", "julia", "sys.so"), "not really a sysimage")
    write(joinpath(root, "share", "julia", "stdlib", "v1.12", "Project.toml"), "name = \"Stdlib\"\n")

    return root
end

const APP = joinpath(pkgdir(AppBundler), "examples", "GtkApp")

@testset "Tarball naming" begin

    tarball = Tarball(APP; os = :linux, arch = :x86_64, compress = true)

    @test AppBundler.suffix(tarball) == ".tar.gz"

    # A tarball is produced for every operating system, so the archive name has to carry the
    # OS. Without it a release matrix uploads three different archives under one asset name
    # and the juliaup database can not tell them apart.
    @test AppBundler.canonical_target_name(tarball) ==
        "$(tarball.parameters["APP_NAME"])-$(tarball.parameters["APP_VERSION"])-linux-x86_64"

    @test AppBundler.canonical_target_name(Tarball(APP; os = :macos, arch = :aarch64)) !=
        AppBundler.canonical_target_name(Tarball(APP; os = :linux, arch = :aarch64))

    @test AppBundler.suffix(Tarball(APP; os = :linux, compress = false)) == ""
end

@testset "Packing a distribution tree" begin

    staging = mktempdir()
    root = fake_distribution(joinpath(staging, "myapp-1.2.0"))

    destination = joinpath(mktempdir(), "myapp-1.2.0-linux-x86_64.tar.gz")
    TarPack.pack(root, destination)

    @test isfile(destination)

    entries = archive_entries(destination)
    @test !isempty(entries)

    # juliaup unpacks with `sans_parent(…, 1)`: exactly one leading component is stripped, so
    # the archive must have a single root directory or the tree lands in the wrong place.
    @test unique(first(splitpath(entry.path)) for entry in entries) == ["myapp-1.2.0"]

    # After that strip, `resolve_julia_binary_path` looks for `<root>/bin/julia`
    paths = [entry.path for entry in entries]
    @test "myapp-1.2.0/bin/julia" in paths

    julia = only(filter(e -> e.path == "myapp-1.2.0/bin/julia", entries))
    @test julia.type == :file
    @test julia.mode == 0o755   # the executable bit has to survive the round trip
end

@testset "Packing preserves symlinks" begin

    staging = mktempdir()
    root = fake_distribution(joinpath(staging, "myapp-1.2.0"))

    # Julia distributions ship versioned shared libraries as symlinks
    symlink("sys.so", joinpath(root, "lib", "julia", "sys.so.1"))

    destination = joinpath(mktempdir(), "myapp.tar.gz")
    TarPack.pack(root, destination)

    link = only(filter(e -> e.path == "myapp-1.2.0/lib/julia/sys.so.1", archive_entries(destination)))

    @test link.type == :symlink
    @test link.link == "sys.so"
end

@testset "Packing rejects an ambiguous root" begin

    staging = mktempdir()
    root = fake_distribution(joinpath(staging, "myapp-1.2.0"))
    mkpath(joinpath(staging, "stray"))

    # Two roots would make juliaup's single strip produce a truncated tree
    @test_throws ErrorException TarPack.pack(root, joinpath(mktempdir(), "bad.tar.gz"))
end

@testset "Bundled tarball is juliaup compatible" begin

    tarball = Tarball(APP; os = :linux, arch = :x86_64, compress = true)

    destination = joinpath(mktempdir(), "$(AppBundler.canonical_target_name(tarball)).tar.gz")

    bundle(tarball, destination) do app_stage
        fake_distribution(app_stage)
    end

    @test isfile(destination)

    paths = [entry.path for entry in archive_entries(destination)]

    # One root, named after the archive, with the interpreter directly under it
    root = only(unique(first(splitpath(path)) for path in paths))
    @test root == AppBundler.canonical_target_name(tarball)
    @test "$root/bin/julia" in paths

    # Refuses to clobber unless asked
    @test_throws ErrorException bundle(identity, tarball, destination)
    bundle(identity, tarball, destination; force = true)
    @test isfile(destination)
end
