#!/usr/bin/env julia
#
# Tests for `build_hfs`. Runs on any OS and is fully deterministic.
#
#   hfsplus       from libdmg_hfsplus_jll: an independent HFS+ reader lists every folder
#                 and reads every file back from the image
#   macOS         fsck_hfs and a read-only kernel mount compared with the stage
#
# Usage:  julia test/hfsplus.jl   (or include it from runtests.jl)

using Test
import AppBundler: HFSImg
import .HFSImg: build_hfs
import libdmg_hfsplus_jll: hfsplus
using Unicode: normalize
using Dates: DateTime, datetime2unix

const MiB = 2^20
const VOLNAME = "HFS Test Ü"
const TIMESTAMP = DateTime(2024, 2, 29, 12, 34, 56)
const TIMESTAMP_UNIX = floor(Int, datetime2unix(TIMESTAMP))
const UUID_A, UUID_B = 0x0123456789abcdef, 0xfedcba9876543210
const HFS_EPOCH = 2082844800
const MAX_PROBLEMS = 20

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"Run a command without throwing; return (exit code, combined output)."
function sh(cmd::Cmd)
    out = IOBuffer()
    p = run(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
    return p.exitcode, String(take!(out))
end

function errmsg(f)
    try
        f()
        return ""
    catch e
        return sprint(showerror, e)
    end
end

be(bytes, off, T) = (x = zero(T); for i in 1:sizeof(T); x = (x << 8) | T(bytes[off + i]); end; x)
image_bytes(img, off, n) = open(io -> (seek(io, off); read(io, n)), img)
"Deterministic bytes; the period of 251 doesn't align with any block size."
pattern(n) = UInt8[(i * 7919) % 251 for i in 1:n]
be_bytes(u::UInt64) = [UInt8((u >> (8 * (7 - i))) & 0xff) for i in 0:7]

"Volume header and catalog B-tree header fields, read straight from the image."
function volume_info(img)
    vh = image_bytes(img, 1024, 512)
    bs = Int(be(vh, 40, UInt32))
    cat = image_bytes(img, Int(be(vh, 288, UInt32)) * bs, 64)
    date(off) = Int(be(vh, off, UInt32)) - HFS_EPOCH
    return (create = date(16), modify = date(20), checked = date(28), uuid = vh[105:112],
            files = Int(be(vh, 32, UInt32)), folders = Int(be(vh, 36, UInt32)),
            blocksize = bs, totalblocks = Int(be(vh, 44, UInt32)),
            depth = Int(be(cat, 14, UInt16)), leafrecords = Int(be(cat, 20, UInt32)))
end

"True if two images differ, and only in the UUID bytes of the two volume headers."
function only_uuid_differs(x, y)
    A, B = read(x), read(y)
    length(A) == length(B) || return false
    n = length(A) ÷ 512 * 512
    allowed = Set([(1024 .+ (104:111))..., ((n - 1024) .+ (104:111))...])
    d = [i - 1 for i in eachindex(A) if A[i] != B[i]]
    return !isempty(d) && issubset(d, allowed)
end

"(files incl. links, folders) as build_hfs counts them."
function count_stage(dir)
    files = folders = 0
    for n in readdir(dir)
        p = joinpath(dir, n)
        if isdir(lstat(p))
            f, d = count_stage(p)
            files += f; folders += d + 1
        else
            files += 1
        end
    end
    return files, folders
end

# ---------------------------------------------------------------------------
# Staging trees
# ---------------------------------------------------------------------------

struct Link; target::String; end

"""
Create `dir` from `path => spec` pairs, making parent folders as needed. A spec is file
contents (string or bytes), `(contents, mode)`, `:dir` for an empty folder, or `Link(target)`.
"""
function write_tree(dir, entries)
    for (rel, spec) in entries
        p = joinpath(dir, rel)
        mkpath(dirname(p))
        if spec === :dir
            mkpath(p)
        elseif spec isa Link
            symlink(spec.target, p)
        elseif spec isa Tuple
            write(p, spec[1]); chmod(p, spec[2])
        else
            write(p, spec)
        end
    end
    return dir
end

function make_stage(stage)
    app, res = "Test.app/Contents", "Test.app/Contents/Resources"
    write_tree(stage, [
        "$app/Info.plist"       => "<plist version=\"1.0\"><dict/></plist>\n",
        "$app/MacOS/launcher"   => ("#!/bin/sh\necho \"hello from hfs\"\n", 0o755),
        "$app/MacOS/plist link" => Link("../Info.plist"),
        "$app/res link"         => Link("Resources"),
        "Applications"          => Link("/Applications"),
        "$res/dangling"         => Link("does/not/exist"),
        "$res/secret.txt"       => ("secret\n", 0o600),
        "$res/empty dir"        => :dir,
        "$res/old.txt"          => "old\n",
        "$res/deep/" * join(("level$i" for i in 1:12), "/") * "/bottom.txt" => "bottom\n",
        # Sizes around block boundaries
        ("$res/size_$n.bin" => pattern(n) for n in (0, 4096, 4097, MiB + 123))...,
        # Decomposition, case folding, ':' <-> '/'
        ("$res/Ünïcödé/$n" => "name: $n\n" for n in ("café.txt", "日本語.txt", "ZEBRA", "apple",
                                                    "a:b.txt", "emoji 🙂.txt", "\u2126 ohm.txt"))...,
    ])
    run(`touch -h -t 196001011200.00 $(joinpath(stage, res, "old.txt"))`)   # before 1970: the epoch
    return stage
end

"A catalog with several index levels: one big folder plus 255-unit names (large keys)."
make_many_stage(dir) = write_tree(dir, [
    ("flat/f_$(lpad(i, 5, '0')).txt" => "flat $i\n" for i in 1:1000)...,
    ("long/" * lpad(i, 6, '0') * "_" * "x"^248 => "long $i\n" for i in 1:1000)...,
])

# ---------------------------------------------------------------------------
# Independent reader: libdmg-hfsplus
# ---------------------------------------------------------------------------

"`hfsplus <img> ls <path>` as name => (mode, size), where size is the valence for folders."
function hfsplus_ls(img, path)
    out = join(Char.(read(ignorestatus(`$(hfsplus()) $img ls $path`))))   # names print as low bytes
    entries = Dict{String,Tuple{Int,Int}}()
    for l in split(out, '\n')
        m = match(r"^([0-7]{6,}) +\d+ +\d+ +(\d+) .{16} (.*)$", l)
        m === nothing && continue
        # Hidden HFS+ metadata folders (hard-link targets); other control characters are
        # just the low bytes of combining marks in decomposed names, e.g. U+0308 -> 0x08
        (startswith(m[3], '\0') || m[3] == ".HFS+ Private Directory Data\r") && continue
        entries[m[3]] = (parse(Int, m[1]; base = 8), parse(Int, m[2]))
    end
    return entries
end

"""
Walk the stage and check the image through `hfsplus`: entry counts per folder, and for
ASCII names mode, size (or valence, or link length) and, with `cat`, file contents.
"""
function hfsplus_compare(img, sdir, path = "/"; cat = true, problems = String[])
    note(msg) = (length(problems) < MAX_PROBLEMS && push!(problems, msg); nothing)
    listed, names = hfsplus_ls(img, path), readdir(sdir)
    length(listed) == length(names) || note("$path: $(length(listed)) listed, stage has $(length(names))")
    for n in names
        (isascii(n) && !occursin(':', n)) || continue
        p, st = joinpath(sdir, n), lstat(joinpath(sdir, n))
        ip = path == "/" ? "/$n" : "$path/$n"
        e = get(listed, n, nothing)
        e === nothing && (note("$ip: not listed"); continue)
        e[1] == st.mode & 0o177777 || note("$ip: mode $(string(e[1], base = 8))")
        if islink(st)
            e[2] == ncodeunits(readlink(p)) || note("$ip: link length $(e[2])")
        elseif isdir(st)
            e[2] == length(readdir(p)) || note("$ip: valence $(e[2])")
            hfsplus_compare(img, p, ip; cat, problems)
        elseif e[2] != st.size
            note("$ip: size $(e[2]) ≠ $(st.size)")
        elseif cat && read(`$(hfsplus()) $img cat $ip`) != read(p)
            note("$ip: contents differ")
        end
    end
    return problems
end

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------

function with_attached(f, img; mountpoint = nothing)
    cmd = `hdiutil attach -nobrowse -noverify -noautofsck -readonly -imagekey diskimage-class=CRawDiskImage`
    cmd = mountpoint === nothing ? `$cmd -nomount` : (mkpath(mountpoint); `$cmd -mountpoint $mountpoint`)
    code, out = sh(`$cmd $img`)
    m = match(r"(/dev/disk\d+)", out)
    (code == 0 && m !== nothing) || error("hdiutil attach $img failed:\n$out")
    dev = String(m[1])
    try
        return f(dev)
    finally
        for _ in 1:10
            sh(`hdiutil detach -quiet $dev`)[1] == 0 && break
            sleep(1)
        end
    end
end

function fsck_ok(dev)
    code, out = sh(`fsck_hfs -fn $(replace(dev, "/dev/disk" => "/dev/rdisk"))`)
    if !occursin("** Checking", out)                 # device not readable: diskutil runs it privileged
        code, out = sh(`diskutil verifyVolume $dev`)
    end
    ok = code == 0 && occursin("appears to be OK", out)
    ok || println(out)
    return ok
end

"Compare a kernel-mounted tree with the stage; names matched after NFC normalization."
function compare_tree(sdir, mdir; mtime = st -> max(0, floor(Int, st.mtime)), problems = String[])
    note(msg) = (length(problems) < MAX_PROBLEMS && push!(problems, msg); nothing)
    nfc(s) = normalize(s, :NFC)
    mlist = Dict(nfc(n) => n for n in readdir(mdir))
    Set(keys(mlist)) == Set(nfc.(readdir(sdir))) || note("$mdir: entries differ")
    for n in readdir(sdir)
        haskey(mlist, nfc(n)) || continue
        s, m = joinpath(sdir, n), joinpath(mdir, mlist[nfc(n)])
        ss, ms = lstat(s), lstat(m)
        ispath(lstat(joinpath(mdir, uppercase(n)))) || note("$m: case-insensitive lookup")
        ss.mode == ms.mode || note("$m: mode")
        mtime(ss) == floor(Int, ms.mtime) || note("$m: mtime")
        if islink(ss)
            readlink(s) == readlink(m) || note("$m: link target")
        elseif isdir(ss)
            compare_tree(s, m; mtime, problems)
        else
            read(s) == read(m) || note("$m: contents")
        end
    end
    return problems
end

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

const TMP = mktempdir()
const STAGE = joinpath(TMP, "stage")
img(name) = joinpath(TMP, name)

@testset "build_hfs" verbose = true begin

@testset "Build" begin
    make_stage(STAGE)
    build_hfs(STAGE, img("test.img"); volname = VOLNAME, uuid = UUID_B, free_space = 8MiB)
    build_hfs(STAGE, img("ts.img"); volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
    v = volume_info(img("test.img"))
    @test (v.files, v.folders) == count_stage(STAGE)
    @test v.totalblocks * v.blocksize == filesize(img("test.img"))
end

@testset "Reproducibility" begin
    b = img("b.img")
    build_hfs(STAGE, b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP_UNIX)
    @test read(b) == read(img("ts.img"))                     # DateTime == Unix seconds
    run(`cp -Rp $STAGE $(img("copy"))`)                      # new inodes and ctimes
    build_hfs(img("copy"), b; volname = VOLNAME, uuid = UUID_A, timestamp = TIMESTAMP)
    @test read(b) == read(img("ts.img"))

    v = volume_info(img("ts.img"))
    @test v.create == v.modify == v.checked == TIMESTAMP_UNIX
    @test v.uuid == be_bytes(UUID_A)
    build_hfs(STAGE, b; volname = VOLNAME, uuid = UUID_B, timestamp = TIMESTAMP)
    @test only_uuid_differs(img("ts.img"), b)
    build_hfs(STAGE, b; volname = VOLNAME, timestamp = TIMESTAMP)        # generated uuid
    @test only_uuid_differs(img("ts.img"), b)
    @test any(!iszero, volume_info(b).uuid)
    @test occursin("uuid", errmsg(() -> build_hfs(STAGE, b; uuid = 0)))

    # Without a timestamp the volume is dated by the newest mtime, not the build time
    dated = mkpath(img("dated"))
    write(joinpath(dated, "a.txt"), "a\n")
    run(`touch -t 202001021230.45 $(joinpath(dated, "a.txt")) $dated`)
    build_hfs(dated, b; uuid = UUID_A)
    @test volume_info(b).create == floor(Int, mtime(dated))
end

# @testset "Rejects names that collide case-insensitively" begin
#     src = mkpath(img("collide src"))
#     write(joinpath(src, "README"), "1"); write(joinpath(src, "Readme"), "2")
#     if length(readdir(src)) == 2                             # case-sensitive temp dir
#         @test occursin(r"collid"i, errmsg(() -> build_hfs(src, img("collide.img"))))
#     else
#         @test_skip "needs a case-sensitive file system"
#     end
# end

@testset "Catalog with several index levels" begin
    stage = make_many_stage(img("many"))
    build_hfs(stage, img("many.img"); volname = "Many")
    v = volume_info(img("many.img"))
    nfiles, nfolders = count_stage(stage)
    @test (v.files, v.folders) == (nfiles, nfolders)
    @test v.leafrecords == 2 * (nfiles + nfolders + 1)        # record + thread each, plus root
    @test v.depth >= 3
end

@testset "Read back with libdmg-hfsplus" begin
    @test isempty(hfsplus_compare(img("test.img"), STAGE))
    @test isempty(hfsplus_compare(img("ts.img"), STAGE))
    @test isempty(hfsplus_compare(img("many.img"), img("many"); cat = false))
    @test read(`$(hfsplus()) $(img("many.img")) cat /flat/f_00999.txt`) == b"flat 999\n"
end

if Sys.isapple()
    @testset "macOS" begin
        mnt = img("mnt")
        for name in ("test.img", "many.img")
            @test with_attached(fsck_ok, img(name))
        end
        with_attached(img("test.img"); mountpoint = mnt) do dev
            @test isempty(compare_tree(STAGE, mnt))
            @test sh(`$mnt/Test.app/Contents/MacOS/launcher`) == (0, "hello from hfs\n")
        end
        with_attached(img("ts.img"); mountpoint = mnt) do dev
            @test isempty(compare_tree(STAGE, mnt; mtime = _ -> TIMESTAMP_UNIX))
        end
    end
end

end # @testset
