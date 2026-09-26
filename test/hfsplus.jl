#!/usr/bin/env julia
#
# Integration test for `build_hfs` (plain script, no Test module).
#
# Builds HFS+ images from a synthetic staging tree full of files, directories and
# links, and checks them:
#
#   Everywhere (byte-level):
#     R. Reproducibility: same stage + uuid (+ timestamp) gives byte-identical images,
#        also from a copied stage with new inodes/ctimes; different uuids differ only
#        in the volume UUID; forced timestamps land in the volume header, and without
#        one the header takes the newest mtime.
#     S. Stress: 100k files (HFS_TEST_MANY_FILES), 255-unit names and a deep catalog;
#        a volume over 4 GiB with a 4.5 GiB file whose data crosses the 2^31/2^32 marks.
#        Checked by reading the catalog and extents straight from the image bytes.
#
#   On macOS (Apple's tooling judges the result):
#     1. fsck_hfs            Apple's checker verifies the on-disk structures.
#     2. hdiutil attach -ro  The kernel mounts the image. Every entry is looked up by
#                            name (a catalog B-tree *search*), also with different case
#                            and Unicode normalization, and compared with the stage:
#                            type, permissions, mtime, contents, link targets.
#     T. Forced timestamp    Every file, folder and link on the mounted image carries it.
#     3. hdiutil create      Converted to a compressed UDZO DMG, verified, mounted and
#                            compared again. Optionally also with libdmg-hfsplus' `dmg`
#                            tool (set DMG_TOOL=/path/to/dmg).
#     4. hdiutil attach -rw  The kernel adds files, folders, symlinks and hard links,
#                            renames, deletes and fills the disk (forcing catalog node
#                            splits); fsck_hfs again and everything re-verified.
#     S. Stress images       fsck_hfs, mounted, every one of the 100k files looked up
#                            and compared; the 4.5 GiB file compared end to end.
#
# Usage:  julia test/hfsplus.jl     (or include it); throws if any check fails.

import AppBundler: NewfsHFS
import .NewfsHFS: build_hfs
using Random: MersenneTwister
using Unicode: normalize
using Dates: DateTime, datetime2unix

const MiB = 2^20
const VOLNAME = "HFS Test Ü"
const FREE_SPACE = 16MiB

# ---------------------------------------------------------------------------
# Minimal check bookkeeping
# ---------------------------------------------------------------------------

const PASSED = Ref(0)
const FAILED = String[]
const MAX_PRINTED = 30

function check(ok::Bool, what::AbstractString)
    if ok
        PASSED[] += 1
    else
        push!(FAILED, what)
        length(FAILED) <= MAX_PRINTED && println("    ✗ ", what)
        length(FAILED) == MAX_PRINTED && println("    … further failures are only counted")
    end
    return ok
end

function section(f, title)
    println("▶ ", title)
    p0, f0 = PASSED[], length(FAILED)
    try
        f()
    catch e
        check(false, "$title: unexpected error: " * sprint(showerror, e))
    end
    np, nf = PASSED[] - p0, length(FAILED) - f0
    println(nf == 0 ? "  ✓ $np checks passed" : "  ✗ $nf of $(np + nf) checks failed")
end

"Run a command without throwing; return (exit code, combined stdout+stderr)."
function sh(cmd::Cmd)
    out = IOBuffer()
    p = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
    return p.exitcode, String(take!(out))
end

indent(s) = join(("      " * l for l in split(strip(s), '\n')), '\n')

# ---------------------------------------------------------------------------
# Staging tree
# ---------------------------------------------------------------------------

settime(path, stamp) = run(`touch -h -t $stamp $path`)     # -h: the link itself

function make_stage(stage)
    rng = MersenneTwister(1234)
    app = joinpath(stage, "Test.app", "Contents")
    res = joinpath(app, "Resources")
    mkpath(joinpath(app, "MacOS"))
    mkpath(res)

    write(joinpath(app, "Info.plist"), "<plist version=\"1.0\"><dict/></plist>\n")
    launcher = joinpath(app, "MacOS", "launcher")
    write(launcher, "#!/bin/sh\necho \"hello from hfs\"\n")
    chmod(launcher, 0o755)

    # Sizes around block boundaries, empty files and folders, odd permissions
    write(joinpath(res, "empty.txt"), "")
    write(joinpath(res, "block.bin"), rand(rng, UInt8, 4096))
    write(joinpath(res, "block+1.bin"), rand(rng, UInt8, 4097))
    write(joinpath(res, "big.bin"), rand(rng, UInt8, 5MiB + 123))
    write(joinpath(res, "readonly.txt"), "read only\n");  chmod(joinpath(res, "readonly.txt"), 0o444)
    write(joinpath(res, "secret.txt"), "secret\n");       chmod(joinpath(res, "secret.txt"), 0o600)
    mkpath(joinpath(res, "empty dir"))
    priv = joinpath(res, "private dir")
    mkpath(priv); write(joinpath(priv, "x"), "x"); chmod(priv, 0o700)
    deep = joinpath(res, "deep", ("level$i" for i in 1:12)...)
    mkpath(deep); write(joinpath(deep, "bottom.txt"), "bottom\n")

    # Enough entries for a multi-level catalog B-tree
    many = joinpath(res, "many")
    mkpath(many)
    for i in 1:3000
        write(joinpath(many, "file_$(lpad(i, 4, '0')).jl"), "# file $i\n")
    end

    # Names that stress Unicode decomposition, case folding and the ':' <-> '/' swap
    uni = joinpath(res, "Ünïcödé")
    mkpath(uni)
    for n in ("café.txt", "Ωμέγα.txt", "日本語.txt", "Æther", "ZEBRA", "apple", "_under",
              "a:b.txt", "emoji 🙂.txt", "ﬁ ligature.txt", "\u2126 ohm sign.txt")
        write(joinpath(uni, n), "name: $n\n")
    end

    # Links
    symlink("../Info.plist", joinpath(app, "MacOS", "plist link"))    # relative, to a file
    symlink("plist link", joinpath(app, "MacOS", "link to link"))     # chain
    symlink("Resources", joinpath(app, "res link"))                   # relative, to a folder
    symlink("/Applications", joinpath(stage, "Applications"))         # absolute (DMG convention)
    symlink("does/not/exist", joinpath(res, "dangling"))              # dangling
    write(joinpath(res, "hard.txt"), "hard\n")
    run(`ln $(joinpath(res, "hard.txt")) $(joinpath(res, "hard2.txt"))`)

    # Fixed timestamps, including one before 1970, which must come out as the epoch
    # (set last: adding entries touches folders)
    write(joinpath(res, "old.txt"), "old\n")
    settime(joinpath(res, "old.txt"), "196001011200.00")
    settime(joinpath(res, "big.bin"), "202001021230.45")
    settime(joinpath(app, "MacOS", "plist link"), "201505050505.05")
    settime(joinpath(res, "empty dir"), "201101011111.11")
    return stage
end

# ---------------------------------------------------------------------------
# Comparing a mounted volume against the stage
# ---------------------------------------------------------------------------

nfc(s) = normalize(s, :NFC)

"Compare two files in chunks, so multi-GiB files don't have to fit in memory."
function same_contents(a, b; chunk = 8MiB)
    filesize(a) == filesize(b) || return false
    open(a) do ia
        open(b) do ib
            ba, bb = Vector{UInt8}(undef, chunk), Vector{UInt8}(undef, chunk)
            while !eof(ia)
                n = readbytes!(ia, ba)
                readbytes!(ib, bb, n) == n || return false
                view(ba, 1:n) == view(bb, 1:n) || return false
            end
            return eof(ib)
        end
    end
end
# HFS+ on macOS cannot show times before 1970; build_hfs stores the epoch for those
macos_mtime(st) = max(0, floor(Int, st.mtime))
exists_nofollow(p) = ispath(lstat(p))

"""
Recursively compare `mdir` (on the mounted image) with `sdir` (stage). Names are
matched after NFC normalization since HFS+ returns decomposed names.
"""
function compare_tree(sdir, mdir; rel = "", case_insensitive = true, expected_mtime = macos_mtime)
    slist = Dict(nfc(n) => n for n in readdir(sdir))
    mlist = Dict(nfc(n) => n for n in readdir(mdir))
    missing_ = setdiff(keys(slist), keys(mlist))
    check(isempty(missing_), "$(rel == "" ? "/" : rel): entries missing on image: $(collect(missing_))")
    extra = setdiff(keys(mlist), keys(slist))
    check(isempty(extra), "$(rel == "" ? "/" : rel): unexpected entries on image: $(collect(extra))")

    for (key, sname) in slist
        haskey(mlist, key) || continue
        s, m = joinpath(sdir, sname), joinpath(mdir, mlist[key])
        r = rel == "" ? sname : joinpath(rel, sname)
        ss, ms = lstat(s), lstat(m)

        # Lookup by the stage's own spelling: the kernel searches the catalog B-tree
        check(exists_nofollow(joinpath(mdir, sname)), "$r: found by name lookup")
        if case_insensitive && uppercase(sname) != sname
            check(exists_nofollow(joinpath(mdir, uppercase(sname))), "$r: found case-insensitively")
        end
        check(ss.mode & 0o170000 == ms.mode & 0o170000, "$r: file type")
        check(ss.mode & 0o7777 == ms.mode & 0o7777,
              "$r: permissions $(string(ss.mode & 0o7777, base = 8)) ≠ $(string(ms.mode & 0o7777, base = 8))")
        expected = expected_mtime(ss)
        check(expected == floor(Int, ms.mtime), "$r: mtime $expected ≠ $(floor(Int, ms.mtime))")

        if islink(ss)
            check(islink(ms) && readlink(s) == readlink(m), "$r: symlink target")
        elseif isdir(ss)
            isdir(ms) && compare_tree(s, m; rel = r, case_insensitive = case_insensitive,
                                      expected_mtime = expected_mtime)
        else
            check(ms.size == ss.size, "$r: size $(ss.size) ≠ $(ms.size)")
            ms.size == ss.size && check(same_contents(s, m), "$r: contents")
        end
    end
end

"Things that only work if the image is actually usable, not just well-formed."
function functional_checks(stage, mnt)
    app = joinpath(mnt, "Test.app", "Contents")
    code, out = sh(`$(joinpath(app, "MacOS", "launcher"))`)
    check(code == 0 && out == "hello from hfs\n", "bundled launcher executes from the image")
    plist = read(joinpath(stage, "Test.app", "Contents", "Info.plist"))
    check(read(joinpath(app, "MacOS", "plist link")) == plist, "relative file symlink resolves")
    check(read(joinpath(app, "MacOS", "link to link")) == plist, "symlink chain resolves")
    check(isfile(joinpath(app, "res link", "big.bin")), "folder symlink resolves")
    check(isdir(joinpath(mnt, "Applications")), "/Applications symlink resolves")
    check(islink(joinpath(app, "Resources", "dangling")) && !ispath(joinpath(app, "Resources", "dangling")),
          "dangling symlink stays dangling")
    check(isfile(joinpath(app, "Resources", "Ünïcödé", "a:b.txt")), "colon in name round-trips")
    check(isfile(joinpath(app, "Resources", "Ünïcödé", normalize("café.txt", :NFD))),
          "decomposed spelling finds the file")
    check(isfile(joinpath(app, "Resources", "Ünïcödé", "\u2126 ohm sign.txt")),
          "U+2126 kept composed (Apple's decomposition exclusions)")
end

# ---------------------------------------------------------------------------
# macOS tooling helpers
# ---------------------------------------------------------------------------

"Attach an image; returns /dev/diskN. `mountpoint = nothing` attaches without mounting."
function attach(img; mountpoint = nothing, readonly = true, raw = true)
    cmd = `hdiutil attach -nobrowse -noverify -noautofsck`
    raw && (cmd = `$cmd -imagekey diskimage-class=CRawDiskImage`)
    readonly && (cmd = `$cmd -readonly`)
    if mountpoint === nothing
        cmd = `$cmd -nomount`
    else
        mkpath(mountpoint)
        cmd = `$cmd -mountpoint $mountpoint`
    end
    code, out = sh(`$cmd $img`)
    m = match(r"(/dev/disk\d+)", out)
    (code == 0 && m !== nothing) || error("hdiutil attach $img failed:\n$(indent(out))")
    return String(m.captures[1])
end

function detach(dev)
    for _ in 1:10
        sh(`hdiutil detach -quiet $dev`)[1] == 0 && return
        sleep(1)
    end
    sh(`hdiutil detach -force -quiet $dev`)
end

function with_attached(f, img; kwargs...)
    dev = attach(img; kwargs...)
    try
        return f(dev)
    finally
        detach(dev)
    end
end

"Apple's checker; falls back to diskutil (runs it privileged) if the device isn't readable."
function fsck_ok(dev)
    rdev = replace(dev, "/dev/disk" => "/dev/rdisk")
    code, out = sh(`fsck_hfs -fn $rdev`)
    if !occursin("** Checking", out)
        code, out = sh(`diskutil verifyVolume $dev`)
    end
    ok = code == 0 && occursin("appears to be OK", out)
    ok || println(indent(out))
    return ok
end

function plist_value(xml, key)
    m = match(Regex("<key>$key</key>\\s*<(string|integer|true|false)\\s*/?>([^<]*)"), xml)
    m === nothing && return nothing
    t = m.captures[1]
    return t == "true" ? true : t == "false" ? false : t == "integer" ? parse(Int, m.captures[2]) : m.captures[2]
end

function volume_checks(mnt; writable)
    xml = sh(`diskutil info -plist $mnt`)[2]
    check(plist_value(xml, "FilesystemType") == "hfs", "diskutil: file system type is hfs")
    # "HFS+" as opposed to "Journaled HFS+", "Case-sensitive HFS+", ...
    name = plist_value(xml, "FilesystemName")
    check(name == "HFS+", "diskutil: plain case-insensitive, non-journaled HFS+ (got $(repr(name)))")
    vname = plist_value(xml, "VolumeName")     # HFS+ returns names decomposed
    check(vname isa AbstractString && nfc(vname) == nfc(VOLNAME),
          "diskutil: volume name $(repr(VOLNAME)) (got $(repr(vname)))")
    check(plist_value(xml, "WritableVolume") == writable, "diskutil: writable = $writable")
end

function free_bytes(mnt)
    lines = split(strip(sh(`df -k $mnt`)[2]), '\n')
    return parse(Int, split(lines[end])[4]) * 1024       # "Available" column
end

# ---------------------------------------------------------------------------
# Byte-level image inspection (works on any OS)
# ---------------------------------------------------------------------------

const HFS_EPOCH = 2082844800
const UUID_RANGE = 105:112          # finderInfo[6:7] within a 512-byte volume header (1-based)

read_be32(bytes, off) = ntoh(reinterpret(UInt32, bytes[off+1:off+4])[1])

"Volume header fields: dates as Unix seconds, and the 8 UUID bytes."
function header_info(img)
    h = open(io -> (seek(io, 1024); read(io, 512)), img)
    return (create = Int(read_be32(h, 16)) - HFS_EPOCH, modify = Int(read_be32(h, 20)) - HFS_EPOCH,
            checked = Int(read_be32(h, 28)) - HFS_EPOCH, uuid = h[UUID_RANGE])
end

"Byte offsets (0-based) where two equally long files differ."
function diff_offsets(a, b)
    A, B = read(a), read(b)
    length(A) == length(B) || return nothing
    return [i - 1 for i in eachindex(A) if A[i] != B[i]]
end

"Offsets of the UUID in the primary and alternate volume headers."
function uuid_offsets(img)
    size = filesize(img) ÷ 512 * 512
    return Set([(1024 .+ UUID_RANGE .- 1)..., ((size - 1024) .+ UUID_RANGE .- 1)...])
end

"Newest mtime in a tree, walked like build_hfs does (symlinks not followed)."
function newest_mtime(dir)
    newest = floor(Int, lstat(dir).mtime)
    for n in readdir(dir)
        st = lstat(joinpath(dir, n))
        newest = max(newest, floor(Int, st.mtime))
        isdir(st) && (newest = max(newest, newest_mtime(joinpath(dir, n))))
    end
    return newest
end

# ---------------------------------------------------------------------------
# Stress stages: many files, and a volume beyond 4 GiB
# ---------------------------------------------------------------------------

const KiB = 1024
const GiB = 2^30
const MANY_FILES = parse(Int, get(ENV, "HFS_TEST_MANY_FILES", "100000"))
const LONG_NAMES = 2000
const MANY_LINKS = 1000
const BIG_SIZE = 4GiB + 512MiB + 123                      # crosses 2^31 and 2^32
const MARKERS = (0, 2^31 - 512KiB, 2^32 - 512KiB, BIG_SIZE - 1MiB)
const LARGE_FREE = 2GiB

"Half the files in one folder, half spread over folders of 100, plus maximal names and links."
function make_many_stage(dir, n)
    flat = joinpath(dir, "flat")
    mkpath(flat)
    for i in 1:(n ÷ 2)
        write(joinpath(flat, "f_$(lpad(i, 6, '0')).txt"), "flat $i\n")
    end
    for i in (n ÷ 2 + 1):n
        d = joinpath(dir, "tree", "d_$(lpad(cld(i, 100), 5, '0'))")
        isdir(d) || mkpath(d)
        write(joinpath(d, "t_$(lpad(i, 6, '0')).txt"), "tree $i\n")
    end
    long = joinpath(dir, "long names")                    # 255 units: the largest catalog keys
    mkpath(long)
    for i in 1:LONG_NAMES
        write(joinpath(long, lpad(i, 6, '0') * "_" * "x"^248), "long $i\n")
    end
    links = joinpath(dir, "links")
    mkpath(links)
    for i in 1:MANY_LINKS
        symlink("../flat/f_$(lpad(i, 6, '0')).txt", joinpath(links, "l_$(lpad(i, 4, '0'))"))
    end
    return dir
end

"A mostly sparse 4.5 GiB file with random markers across the 2 and 4 GiB marks, then small files."
function make_large_stage(dir)
    mkpath(joinpath(dir, "z_dir"))
    rng = MersenneTwister(5)
    open(joinpath(dir, "big.bin"), "w") do io
        truncate(io, BIG_SIZE)
        for off in MARKERS
            seek(io, off)
            write(io, rand(rng, UInt8, 1MiB))
        end
    end
    # Sorted after big.bin, so their data lands beyond the 4 GiB mark of the image
    write(joinpath(dir, "z_after.txt"), "stored beyond the 4 GiB mark\n")
    write(joinpath(dir, "z_dir", "inner.bin"), rand(rng, UInt8, 10_000))
    return dir
end

"Count entries the way build_hfs walks a stage: (files incl. links, folders)."
function count_stage(dir)
    files = folders = 0
    for n in readdir(dir)
        st = lstat(joinpath(dir, n))
        if isdir(st)
            folders += 1
            f, d = count_stage(joinpath(dir, n))
            files += f; folders += d
        else
            files += 1
        end
    end
    return files, folders
end

be(bytes, off, T) = (x = zero(T); for i in 1:sizeof(T); x = (x << 8) | T(bytes[off + i]); end; x)

"""
Walk the catalog leaf chain of an image independently of NewfsHFS: tree depth, leaf
record counts, and for every file (and link) its size and byte offset in the image.
"""
function catalog_scan(img)
    open(img) do io
        at(off, n) = (seek(io, off); read(io, n))
        vh = at(1024, 512)
        bs = be(vh, 40, UInt32)
        cat = Int(be(vh, 272 + 16, UInt32)) * bs
        hdr = at(cat, 64)
        depth, nrecs, first = be(hdr, 14, UInt16), be(hdr, 20, UInt32), be(hdr, 24, UInt32)
        ns = Int(be(hdr, 32, UInt16))
        files = Dict{String,Tuple{Int,Int}}()
        seen, node = 0, first
        while node != 0
            nd = at(cat + Int(node) * ns, ns)
            for i in 1:be(nd, 10, UInt16)
                off = Int(be(nd, ns - 2i, UInt16))
                data = off + 2 + Int(be(nd, off, UInt16))
                if be(nd, data, UInt16) == 2                  # file record
                    name = transcode(String, [be(nd, off + 8 + 2j, UInt16) for j in 0:(be(nd, off + 6, UInt16) - 1)])
                    files[name] = (Int(be(nd, data + 88, UInt64)), Int(be(nd, data + 104, UInt32)) * bs)
                end
                seen += 1
            end
            node = be(nd, 0, UInt32)
        end
        return (depth = Int(depth), leafrecords = Int(nrecs), counted = seen, files = files,
                filecount = Int(be(vh, 32, UInt32)), foldercount = Int(be(vh, 36, UInt32)),
                blocksize = Int(bs), totalblocks = Int(be(vh, 44, UInt32)))
    end
end

image_bytes(img, off, n) = open(io -> (seek(io, off); read(io, n)), img)

"On Linux with hfsprogs installed, also run its fsck."
function linux_fsck(img)
    Sys.which("fsck.hfsplus") === nothing && return
    code, out = sh(`fsck.hfsplus -f -n $img`)
    check(code == 0 && occursin("appears to be OK", out), "fsck.hfsplus (hfsprogs) reports OK") || println(indent(out))
end

function stress_checks(tmp, many_stage, many_img, large_stage, large_img)
    section("Many files: $(MANY_FILES) files, $(LONG_NAMES) maximal names, $(MANY_LINKS) links") do
        make_many_stage(many_stage, MANY_FILES)
        t = @elapsed build_hfs(many_stage, many_img; volname = "Many")
        nfiles, nfolders = count_stage(many_stage)
        println("    built $(nfiles) files / $(nfolders) folders into $(filesize(many_img) ÷ MiB) MiB in $(round(t, digits = 1)) s")
        c = catalog_scan(many_img)
        check(c.filecount == nfiles && c.foldercount == nfolders,
              "volume header counts ($(c.filecount), $(c.foldercount)) = stage ($nfiles, $nfolders)")
        expected = 2 * (nfiles + nfolders + 1)                # record + thread per item, plus the root
        check(c.leafrecords == expected, "catalog header: $(c.leafrecords) leaf records, expected $expected")
        check(c.counted == expected, "leaf chain holds all $expected records ($(c.counted) found)")
        check(c.depth >= 3, "catalog tree has several index levels (depth $(c.depth))")
        sample = [joinpath(many_stage, "flat", "f_$(lpad(i, 6, '0')).txt") for i in 1:997:(MANY_FILES ÷ 2)]
        push!(sample, joinpath(many_stage, "long names", lpad(LONG_NAMES, 6, '0') * "_" * "x"^248))
        ok = all(sample) do p
            entry = get(c.files, basename(p), nothing)
            entry !== nothing && image_bytes(many_img, entry[2], entry[1]) == read(p)
        end
        check(ok, "sampled file contents found at their extents in the image")
        linux_fsck(many_img)
    end

    section("Large volume: $(round((BIG_SIZE + LARGE_FREE) / GiB, digits = 1)) GiB with a $(round(BIG_SIZE / GiB, digits = 1)) GiB file") do
        make_large_stage(large_stage)
        t = @elapsed build_hfs(large_stage, large_img; volname = "Large", free_space = LARGE_FREE)
        size = filesize(large_img)
        println("    built $(round(size / GiB, digits = 2)) GiB image in $(round(t, digits = 1)) s, " *
                "$(round(stat(large_img).blocks * 512 / MiB, digits = 1)) MiB on disk")
        check(size > 4GiB, "image is larger than 4 GiB")
        c = catalog_scan(large_img)
        check(c.totalblocks * c.blocksize == size, "volume header totalBlocks × blockSize = image size")
        check(image_bytes(large_img, size - 1024, 512) == image_bytes(large_img, 1024, 512),
              "alternate volume header (beyond 4 GiB) equals the primary")
        check(stat(large_img).blocks * 512 < 1GiB, "zero regions stay sparse in the image")

        big = get(c.files, "big.bin", nothing)
        check(big !== nothing && big[1] == BIG_SIZE, "big.bin recorded with its full 64-bit size")
        if big !== nothing
            src = joinpath(large_stage, "big.bin")
            for off in MARKERS
                check(image_bytes(large_img, big[2] + off, 1MiB) == open(io -> (seek(io, off); read(io, 1MiB)), src),
                      "big.bin marker at offset $off intact")
            end
            check(all(iszero, image_bytes(large_img, big[2] + 3GiB, 1MiB)), "hole inside big.bin reads as zeros")
        end
        after = get(c.files, "z_after.txt", nothing)
        check(after !== nothing && after[2] > 4GiB, "z_after.txt stored beyond the 4 GiB mark")
        after !== nothing && check(image_bytes(large_img, after[2], after[1]) == read(joinpath(large_stage, "z_after.txt")),
                                   "z_after.txt contents intact")
        linux_fsck(large_img)
    end
end

"macOS's view of the stress images."
function macos_stress_checks(many_stage, many_img, large_stage, large_img, mnt)
    section("Many files on macOS: fsck, mount, every file looked up and compared") do
        with_attached(dev -> check(fsck_ok(dev), "fsck_hfs reports the volume OK"), many_img)
        with_attached(many_img; mountpoint = mnt) do dev
            compare_tree(many_stage, mnt)
            check(length(readdir(joinpath(mnt, "flat"))) == MANY_FILES ÷ 2, "flat folder lists all $(MANY_FILES ÷ 2) files")
        end
    end

    section("Large volume on macOS: fsck, mount, 4.5 GiB file compared end to end") do
        with_attached(dev -> check(fsck_ok(dev), "fsck_hfs reports the volume OK"), large_img)
        with_attached(large_img; mountpoint = mnt) do dev
            total = parse(Int, split(split(strip(sh(`df -k $mnt`)[2]), '\n')[end])[2]) * 1024
            check(total > 4GiB, "df reports a volume larger than 4 GiB ($(round(total / GiB, digits = 2)) GiB)")
            free = free_bytes(mnt)
            check(0.8 * LARGE_FREE <= free <= LARGE_FREE + 64MiB,
                  "free space ≈ requested $(LARGE_FREE ÷ GiB) GiB (df: $(round(free / GiB, digits = 2)) GiB)")
            compare_tree(large_stage, mnt)
        end
    end
end

# ---------------------------------------------------------------------------
# Test phases
# ---------------------------------------------------------------------------

"Checks that let macOS itself judge the images."
function macos_checks(tmp, stage, img, ts_img, mnt)
    section("fsck_hfs on the fresh image") do
        with_attached(dev -> check(fsck_ok(dev), "fsck_hfs reports the volume OK"), img)
    end

    section("Forced timestamp on every file, folder and link (mounted)") do
        with_attached(dev -> check(fsck_ok(dev), "fsck_hfs reports the timestamped volume OK"), ts_img)
        with_attached(ts_img; mountpoint = mnt) do dev
            check(floor(Int, stat(mnt).mtime) == TIMESTAMP_UNIX, "volume root carries the timestamp")
            compare_tree(stage, mnt; expected_mtime = st -> TIMESTAMP_UNIX)
        end
    end

    section("macOS derives its Volume UUID from the uuid argument") do
        volume_uuid(image) = with_attached(image; mountpoint = mnt) do dev
            plist_value(sh(`diskutil info -plist $mnt`)[2], "VolumeUUID")
        end
        again = joinpath(tmp, "timestamp again.img")
        build_hfs(stage, again; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
        v1, v2, v3 = volume_uuid(ts_img), volume_uuid(again), volume_uuid(img)
        check(v1 isa AbstractString && tryparse(Base.UUID, v1) !== nothing,
              "diskutil reports a valid Volume UUID ($(repr(v1)))")
        check(v1 == v2, "same uuid → same Volume UUID in macOS ($(repr(v1)) vs $(repr(v2)))")
        check(v1 != v3, "different uuid → different Volume UUID in macOS")
        rm(again)
    end

    section("Read-only mount by the macOS kernel") do
        with_attached(img; mountpoint = mnt) do dev
            volume_checks(mnt; writable = false)
            compare_tree(stage, mnt)
            functional_checks(stage, mnt)
            code, _ = sh(`touch $(joinpath(mnt, "should-fail"))`)
            check(code != 0, "read-only mount refuses writes")
        end
    end

    section("Compressed DMG made by hdiutil (UDZO)") do
        dmg = joinpath(tmp, "hdiutil.dmg")
        code, out = with_attached(dev -> sh(`hdiutil create -quiet -srcdevice $dev -format UDZO -o $dmg`), img)
        check(code == 0, "hdiutil create -srcdevice -format UDZO") || println(indent(out))
        check(sh(`hdiutil verify -quiet $dmg`)[1] == 0, "hdiutil verify (checksums)")
        check(occursin("Format: UDZO", sh(`hdiutil imageinfo $dmg`)[2]), "image format is UDZO")
        with_attached(dmg; mountpoint = mnt, raw = false) do dev
            compare_tree(stage, mnt)
            functional_checks(stage, mnt)
        end
    end

    if haskey(ENV, "DMG_TOOL")
        section("Compressed DMG made by libdmg-hfsplus ($(ENV["DMG_TOOL"]))") do
            dmg = joinpath(tmp, "libdmg.dmg")
            code, out = sh(`$(ENV["DMG_TOOL"]) build $img $dmg`)
            check(code == 0, "dmg build") || println(indent(out))
            check(sh(`hdiutil verify -quiet $dmg`)[1] == 0, "hdiutil verify (checksums)")
            with_attached(dmg; mountpoint = mnt, raw = false) do dev
                compare_tree(stage, mnt)
                functional_checks(stage, mnt)
            end
        end
    end

    many_rel = joinpath("Test.app", "Contents", "Resources", "many")
    uni_rel = joinpath("Test.app", "Contents", "Resources", "Ünïcödé")
    payload = rand(MersenneTwister(99), UInt8, 3MiB)

    section("Read-write mount: macOS adds files, folders and links") do
        with_attached(img; mountpoint = mnt, readonly = false) do dev
            volume_checks(mnt; writable = true)
            free = free_bytes(mnt)
            check(0.8 * FREE_SPACE <= free <= FREE_SPACE + 2MiB,
                  "free space ≈ requested $(FREE_SPACE ÷ MiB) MiB (df: $(round(free / MiB, digits = 1)) MiB)")

            add = joinpath(mnt, "added")
            mkpath(joinpath(add, "nested", "dir"))
            write(joinpath(add, "new.txt"), "new file\n")
            write(joinpath(add, "nested", "dir", "payload.bin"), payload)
            symlink("new.txt", joinpath(add, "new link"))
            symlink("../Test.app", joinpath(add, "app link"))
            run(`ln $(joinpath(add, "new.txt")) $(joinpath(add, "new hard.txt"))`)
            # The packed leaves are full, so these inserts force node splits
            for i in 1:500
                write(joinpath(mnt, many_rel, "added_$i.jl"), "# added $i\n")
            end
            write(joinpath(mnt, "Test.app", "Contents", "Info.plist"), "changed\n")
            mv(joinpath(mnt, uni_rel, "apple"), joinpath(mnt, uni_rel, "Apple renamed"))
            rm(joinpath(mnt, uni_rel, "ZEBRA"))
            chmod(joinpath(mnt, "Test.app", "Contents", "Resources", "secret.txt"), 0o640)

            # Exhaust the free space: the kernel must refuse cleanly, and deleting must free it again
            big = joinpath(add, "too big.bin")
            code, _ = sh(`dd if=/dev/zero of=$big bs=1m count=$(2 * FREE_SPACE ÷ MiB)`)
            check(code != 0, "writing beyond the free space fails (disk full)")
            rm(big; force = true)
            run(`sync`)
        end

        with_attached(dev -> check(fsck_ok(dev), "fsck_hfs OK after the kernel modified the volume"), img)

        with_attached(img; mountpoint = mnt) do dev
            add = joinpath(mnt, "added")
            check(isdir(joinpath(add, "nested", "dir")), "new nested folders persist")
            check(read(joinpath(add, "new.txt"), String) == "new file\n", "new file persists")
            check(read(joinpath(add, "nested", "dir", "payload.bin")) == payload, "3 MiB payload intact")
            check(readlink(joinpath(add, "new link")) == "new.txt", "new symlink persists")
            check(isfile(joinpath(add, "app link", "Contents", "MacOS", "launcher")), "new folder symlink resolves")
            a, b = stat(joinpath(add, "new.txt")), stat(joinpath(add, "new hard.txt"))
            check(a.inode == b.inode && a.nlink == 2, "hard link created by macOS shares the inode")
            added = count(n -> startswith(n, "added_"), readdir(joinpath(mnt, many_rel)))
            check(added == 500, "500 files added to the full folder ($added found)")
            lookups = all(i -> isfile(joinpath(mnt, many_rel, "file_$(lpad(i, 4, '0')).jl")), 1:3000) &&
                      all(i -> isfile(joinpath(mnt, many_rel, "added_$i.jl")), 1:500)
            check(lookups, "all 3500 files found by lookup after node splits")
            check(read(joinpath(mnt, "Test.app", "Contents", "Info.plist"), String) == "changed\n", "modified file persists")
            check(isfile(joinpath(mnt, uni_rel, "Apple renamed")) && !exists_nofollow(joinpath(mnt, uni_rel, "apple")),
                  "rename persists")
            check(!exists_nofollow(joinpath(mnt, uni_rel, "ZEBRA")), "delete persists")
            check(stat(joinpath(mnt, "Test.app", "Contents", "Resources", "secret.txt")).mode & 0o777 == 0o640,
                  "chmod persists")
            check(!exists_nofollow(joinpath(add, "too big.bin")), "deleted file is gone")
            code, out = sh(`$(joinpath(mnt, "Test.app", "Contents", "MacOS", "launcher"))`)
            check(out == "hello from hfs\n", "original content still executes")
        end
    end

    section("Rejects names that collide on case-insensitive HFS+") do
        # Needs a case-sensitive source; make one with hdiutil
        cs, csmnt = joinpath(tmp, "cs.dmg"), joinpath(tmp, "csmnt")
        code, out = sh(`hdiutil create -quiet -size 4m -fs "Case-sensitive HFS+" -volname CS $cs`)
        check(code == 0, "create case-sensitive scratch volume") || return
        with_attached(cs; mountpoint = csmnt, readonly = false, raw = false) do dev
            src = joinpath(csmnt, "collide")
            mkpath(src)
            write(joinpath(src, "README"), "1")
            write(joinpath(src, "Readme"), "2")
            msg = try
                build_hfs(src, joinpath(tmp, "collide.img"))
                ""
            catch e
                sprint(showerror, e)
            end
            check(occursin("collide", msg), "build_hfs refuses README + Readme with a clear error")
        end
    end

end

const TIMESTAMP = DateTime(2024, 2, 29, 12, 34, 56)
const TIMESTAMP_UNIX = floor(Int, datetime2unix(TIMESTAMP))
const UUID_A = 0x0123456789abcdef
const UUID_B = 0xfedcba9876543210
be_bytes(u::UInt64) = [UInt8((u >> (8 * (7 - i))) & 0xff) for i in 0:7]

"Everything that can be checked from the image bytes alone; runs on any OS."
function reproducibility_checks(tmp, stage)
    a, b = joinpath(tmp, "a.img"), joinpath(tmp, "b.img")
    same(x, y) = read(x) == read(y)
    only_uuid_differs(x, y) = (d = diff_offsets(x, y); d !== nothing && !isempty(d) && issubset(d, uuid_offsets(x)))

    section("Reproducibility: uuid and forced timestamp") do
        build_hfs(stage, a; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
        build_hfs(stage, b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
        check(same(a, b), "same uuid + timestamp: byte-identical images")

        build_hfs(stage, b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP_UNIX)
        check(same(a, b), "timestamp as Unix seconds equals the DateTime form")

        copy = joinpath(tmp, "stage copy")
        run(`cp -Rp $stage $copy`)              # new inodes, ctimes and atimes
        build_hfs(copy, b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
        check(same(a, b), "copied stage gives the identical image")
        rm(copy; recursive = true)

        h = header_info(a)
        check(h.create == h.modify == h.checked == TIMESTAMP_UNIX,
              "volume header dates are the forced timestamp ($(h.create), $(h.modify), $(h.checked))")
        check(h.uuid == be_bytes(UUID_A), "volume header stores the given uuid (got $(bytes2hex(h.uuid)))")

        build_hfs(stage, b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP_UNIX + 1)
        check(!same(a, b), "a different timestamp changes the image")

        build_hfs(stage, b; volname = VOLNAME, uuid = UUID_B, timestamp = TIMESTAMP)
        check(only_uuid_differs(a, b), "a different uuid changes only the volume UUID bytes")

        build_hfs(stage, a; volname = VOLNAME, timestamp = TIMESTAMP)
        build_hfs(stage, b; volname = VOLNAME, timestamp = TIMESTAMP)
        check(only_uuid_differs(a, b), "by default the UUID is random and nothing else changes")
        check(any(!iszero, header_info(a).uuid), "random UUID is non-zero")

        for bad in (0, -1, big(2)^64)
            msg = try
                build_hfs(stage, b; uuid = bad)
                ""
            catch e
                sprint(showerror, e)
            end
            check(occursin("uuid", msg), "uuid = $bad is rejected")
        end
    end

    section("Reproducibility: dates from the files themselves") do
        build_hfs(stage, a; volname = VOLNAME, uuid = UUID_A)
        sleep(1.1)                                  # a build-time date would now differ
        build_hfs(stage, b; volname = VOLNAME, uuid = UUID_A)
        check(same(a, b), "same uuid, no timestamp: byte-identical images")
        h, newest = header_info(a), newest_mtime(stage)
        check(h.create == h.modify == h.checked == newest,
              "volume dated by the newest mtime in the stage ($newest, got $(h.create))")
    end

    rm(a; force = true); rm(b; force = true)
end

function main()
    tmp = mktempdir()
    stage, img, mnt = joinpath(tmp, "stage"), joinpath(tmp, "test.img"), joinpath(tmp, "mnt")
    ts_img = joinpath(tmp, "timestamp.img")
    println("Working in $tmp")

    section("Build image from stage") do
        make_stage(stage)
        t = @elapsed build_hfs(stage, img; volname = VOLNAME, free_space = FREE_SPACE)
        check(isfile(img), "image created")
        println("    built $(filesize(img) ÷ MiB) MiB image in $(round(t, digits = 2)) s")
        build_hfs(stage, ts_img; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
    end

    reproducibility_checks(tmp, stage)
    many_stage, many_img = joinpath(tmp, "many"), joinpath(tmp, "many.img")
    large_stage, large_img = joinpath(tmp, "large"), joinpath(tmp, "large.img")
    stress_checks(tmp, many_stage, many_img, large_stage, large_img)

    if Sys.isapple()
        macos_checks(tmp, stage, img, ts_img, mnt)
        macos_stress_checks(many_stage, many_img, large_stage, large_img, mnt)
    else
        println("▶ Skipping the macOS checks (they need hdiutil, fsck_hfs and diskutil)")
    end

    println()
    println(isempty(FAILED) ? "ALL $(PASSED[]) CHECKS PASSED" : "$(length(FAILED)) FAILED, $(PASSED[]) passed")
    if isempty(FAILED)
        rm(tmp; recursive = true, force = true)
    else
        println("Kept $tmp for inspection")
    end
    return isempty(FAILED) ? 0 : 1
end


main()
