"""
    AppImagePack

Assembly of an AppImage from a staged AppDir.

An AppImage is nothing more than a **runtime ELF followed by a squashfs image**. The runtime knows
where the filesystem begins because it is appended immediately after itself, mounts it through FUSE,
and executes `AppRun` from the mount point. Nothing is written to disk, which is why AppImages suit
HPC: a Julia distribution is tens of thousands of small files, and unpacking one onto a network
filesystem is exactly the cost this format avoids.

The runtime carries the magic bytes `AI\\x02` at offset 8 already, so assembly is a concatenation
with no patching.
"""
module AppImagePack

import squashfs_tools_jll: mksquashfs, unsquashfs

"""
Compressors accepted for the squashfs payload.

The runtime bundles squashfuse built against zstd and zlib only, so anything else produces an image
it cannot mount. `mksquashfs` also offers `xz` and `lz4`; both are rejected here, verified against
the upstream runtime, which reports `Failed to extract AppImage` for an xz payload. Between the two
that remain, zstd decompresses far faster than gzip, which is the point of mounting rather than
unpacking.
"""
const COMPRESSORS = [:zstd, :gzip]

"""
    pack(appdir::String, destination::String, runtime::String; compression = :zstd)

Compress `appdir` into a squashfs image placed after `runtime`, producing an executable AppImage at
`destination`.
"""
function pack(appdir::String, destination::String, runtime::String; compression::Symbol = :zstd)

    compression in COMPRESSORS ||
        error("`$compression` is not a supported AppImage compressor. Choose one of: " *
              join(COMPRESSORS, ", ") * ".")

    isfile(runtime) || error("The AppImage runtime `$runtime` does not exist")

    isfile(joinpath(appdir, "AppRun")) ||
        error("`$appdir` has no AppRun; the runtime executes it after mounting and refuses to " *
              "start without it.")

    mkpath(dirname(destination))

    prefix = filesize(runtime)

    # `-offset` reserves room for the runtime so the filesystem is written straight into the final
    # file. Building the squashfs separately and concatenating would need a second full-size
    # temporary copy, which for a Julia distribution is hundreds of megabytes — usually landing in
    # /tmp, and on a machine with a small tmpfs that fails as an opaque "out of space".
    #
    # -root-owned keeps the build user out of the image, -noappend makes the build reproducible
    # when the destination already exists.
    run(`$(mksquashfs()) $appdir $destination -root-owned -noappend -comp $compression -b 128K -offset $prefix`)

    # mksquashfs zeroes the bytes it skipped rather than preserving them, so the runtime goes in
    # afterwards, over the reserved prefix.
    open(destination, "r+") do file
        seekstart(file)
        write(file, read(runtime))
    end

    Sys.isunix() && chmod(destination, 0o755)

    return destination
end

"""
    offset(path::String) -> Int

Byte offset at which the squashfs payload begins, i.e. the size of the runtime prefix. This is the
number `<app>.AppImage --appimage-offset` reports, and what `unsquashfs -o` needs.
"""
function offset(path::String)

    # The payload begins where the ELF ends, and an ELF ends after its section header table. This
    # is how the runtime itself answers `--appimage-offset`.
    #
    # Scanning for the squashfs magic instead would be wrong: the runtime embeds squashfuse, whose
    # own "hsqs" constant appears hundreds of kilobytes before the real payload.
    header = open(path) do file
        read(file, 64)
    end

    length(header) >= 64 && header[1:4] == UInt8[0x7f, 0x45, 0x4c, 0x46] ||
        error("`$path` does not start with an ELF header, so it is not an AppImage.")

    little_endian(bytes) = foldr((byte, acc) -> acc << 8 | byte, bytes; init = UInt64(0))

    if header[5] == 0x02 # 64 bit
        shoff, shentsize, shnum = little_endian(header[41:48]), little_endian(header[59:60]), little_endian(header[61:62])
    else                 # 32 bit
        shoff, shentsize, shnum = little_endian(header[33:36]), little_endian(header[47:48]), little_endian(header[49:50])
    end

    return Int(shoff + shentsize * shnum)
end

"""
    unpack(source::String, destination::String)

Extract the payload of an AppImage without mounting it.

This is the fallback for a machine with no usable FUSE — the AppImage's own
`--appimage-extract` needs to run the runtime, which is precisely what fails there.
"""
function unpack(source::String, destination::String)

    run(`$(unsquashfs()) -f -o $(offset(source)) -d $destination $source`)

    return destination
end

end
