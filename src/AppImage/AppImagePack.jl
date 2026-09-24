"""
    AppImage

Pack an AppDir into a type-2 AppImage and unpack it again.

The format is a prebuilt static ELF runtime with a SquashFS image concatenated
onto it. The runtime derives the payload offset from its own ELF size, so
packing is a compress-and-concatenate with no header fixup; unpacking has to
recover that offset before `unsquashfs` can find the superblock.
"""
module AppImagePack

import squashfs_tools_jll: mksquashfs, unsquashfs
import ..AppImageRuntime: get_runtime

export pack, unpack

const COMPRESSORS = [:zstd, :gzip]

# ------------------------------------------------------------------ offset --

"""
    elf_size(path) -> Int

Size of the ELF image at `path`, computed from its header as
`e_shoff + e_shentsize * e_shnum`. For an AppImage runtime this is where the
appended SquashFS payload begins -- the same arithmetic the runtime itself
performs at startup, so it does not require executing the file.
"""
function elf_size(path::AbstractString)
    hdr = open(io -> read(io, 64), path, "r")
    length(hdr) >= 64 || error("$path is too short to be an ELF file")
    hdr[1:4] == UInt8[0x7f, 0x45, 0x4c, 0x46] || error("$path is not an ELF file")
    hdr[6] == 0x01 || error("only little-endian ELF is supported")

    # e_shoff / e_shentsize / e_shnum sit at different offsets for ELF32/ELF64.
    read_at(T, off) = only(reinterpret(T, hdr[off+1 : off+sizeof(T)]))

    if hdr[5] == 0x02        # ELFCLASS64
        shoff     = Int(read_at(UInt64, 0x28))
        shentsize = Int(read_at(UInt16, 0x3A))
        shnum     = Int(read_at(UInt16, 0x3C))
    elseif hdr[5] == 0x01    # ELFCLASS32
        shoff     = Int(read_at(UInt32, 0x20))
        shentsize = Int(read_at(UInt16, 0x2E))
        shnum     = Int(read_at(UInt16, 0x30))
    else
        error("unknown ELF class $(hdr[5])")
    end

    return shoff + shentsize * shnum
end

"""
    payload_offset(appimage) -> Int

Byte offset of the SquashFS payload inside `appimage`, verified against the
`hsqs` superblock magic.
"""
function payload_offset(appimage::AbstractString)
    off = elf_size(appimage)
    magic = open(appimage, "r") do io
        seek(io, off)
        read(io, 4)
    end
    magic == UInt8[0x68, 0x73, 0x71, 0x73] ||
        error("no SquashFS superblock at offset $off; is $appimage a type-2 AppImage?")
    return off
end

# --------------------------------------------------------------- squashfs --

"""
    compress(appdir, payload; comp="zstd") -> String

Compress `appdir` into a SquashFS image at `payload`. Timestamps are pinned to
the epoch and ownership forced to root so repeated builds are bit-identical;
`-all-root` overrides ownership only, not the exec bit or symlinks already
staged in `appdir`.
"""
function compress(appdir::AbstractString, payload::AbstractString;
                  compression::Symbol = :zstd)
    rm(payload; force = true)

    @info "Packing SquashFS payload ($compression)"
    run(`$(mksquashfs()) $appdir $payload -noappend -all-root -no-xattrs -comp $compression -b 128K -mkfs-time 0 -all-time 0`)

    return payload
end

# ----------------------------------------------------------------- concat --

"""
    concatenate(runtime, payload, output) -> String

`runtime * payload`, streamed in chunks. The runtime derives the payload
offset from its own ELF size, so no header fixup is needed.
"""
function concatenate(runtime::AbstractString, payload::AbstractString,
                     output::AbstractString)
    buf = Vector{UInt8}(undef, 1024 * 1024)
    open(output, "w") do out
        for part in (runtime, payload)
            open(part, "r") do io
                while !eof(io)
                    n = readbytes!(io, buf)
                    write(out, view(buf, 1:n))
                end
            end
        end
    end
    chmod(output, 0o755)
    return output
end

# ------------------------------------------------------------ pack/unpack --

"""
    pack(source, destination; arch=host_arch(), comp="zstd", cache=runtime_cache()) -> String

Package the AppDir at `source` into an AppImage at `destination`.

`source` must already be a valid AppDir: an executable `AppRun` at its root,
plus the `.desktop` file, icon and `.DirIcon` the format expects. Nothing here
edits the tree.
"""
function pack(source::AbstractString, destination::AbstractString; compression::Symbol = :zstd, runtime = get_runtime(Sys.ARCH))

    isdir(source) || error("AppDir not found: $source")
    isfile(joinpath(source, "AppRun")) || error("$source has no AppRun at its root")

    mktempdir() do work
        payload = compress(source, joinpath(work, "payload.squashfs"); compression)
        concatenate(runtime, payload, destination)
    end

    @info "Built $(basename(destination))" bytes = filesize(destination) payload_offset = filesize(runtime)

    return destination
end

"""
    unpack(source, destination) -> String

Extract the AppDir from the AppImage at `source` into `destination`.

`unsquashfs` cannot find the superblock on its own here, since the payload is
preceded by the runtime -- hence the explicit `-offset`.
"""
function unpack(source::AbstractString, destination::AbstractString)
    isfile(source) || error("AppImage not found: $source")
    offset = payload_offset(source)

    run(`$(unsquashfs()) -offset $offset -force -dest $destination $source`)

    return destination
end

end # module
