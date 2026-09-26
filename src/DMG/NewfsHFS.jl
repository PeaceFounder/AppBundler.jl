"""
    NewfsHFS

Pure-Julia HFS+ image creation, replacing hfsprogs' `newfs_hfs` and
libdmg-hfsplus' `hfsplus ... addall`.

`build_hfs` creates a complete, exactly sized volume from a staging directory
in one pass (the recommended path for DMG building):

    include("NewfsHFS.jl"); using .NewfsHFS
    build_hfs("stage", "img_stage"; volname = "My App")   # then: dmg build img_stage out.dmg

`newfs_hfs` formats an existing file as an empty volume, with the same layout
hfsprogs 540.1 produces:

    newfs_hfs("img_stage"; volname = "volume name")

Command line (same calling convention as hfsprogs):

    julia NewfsHFS.jl -v "volume name" img_stage
"""
module NewfsHFS

using Dates: Dates
using Random: RandomDevice
using Unicode: normalize

export newfs_hfs, build_hfs

const MiB = 1024^2
const GiB = 1024^3
const TiB = 1024^4

const HFS_EPOCH = 2082844800            # seconds from 1904-01-01 to 1970-01-01

# B-tree clump sizes in MB for volumes of 1GB, 2GB, 4GB, ... 16TB
# (from Apple's makehfs.c); columns: attributes, catalog, extents
const CLUMP_TABLE = (
    (  4,   4,  4),   #   1 GB
    (  6,   6,  4),   #   2 GB
    (  8,   8,  4),   #   4 GB
    ( 11,  11,  5),   #   8 GB
    ( 64,  32,  5),   #  16 GB
    ( 84,  49,  6),   #  32 GB
    (111,  74,  7),   #  64 GB
    (147, 111,  8),   # 128 GB
    (194, 169,  9),   # 256 GB
    (256, 256, 11),   # 512 GB
    (294, 294, 14),   #   1 TB
    (338, 338, 16),   #   2 TB
    (388, 388, 20),   #   4 TB
    (446, 446, 25),   #   8 TB
    (512, 512, 32),   #  16 TB
)
const ATTR_COL, CAT_COL, EXT_COL = 1, 2, 3

const EXT_NODE_SIZE  = 4096
const ATTR_NODE_SIZE = 8192

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

"Write `x` big-endian into `buf` at 0-based byte offset `off`; return the next offset."
function wbe!(buf::Vector{UInt8}, off::Integer, x::Unsigned)
    n = sizeof(x)
    for i in 1:n
        buf[off + i] = (x >> (8 * (n - i))) % UInt8
    end
    return off + n
end

"Write an HFSUniStr255 (length + UTF-16BE code units)."
function wunistr!(buf::Vector{UInt8}, off::Integer, s::Vector{UInt16})
    off = wbe!(buf, off, UInt16(length(s)))
    for c in s
        off = wbe!(buf, off, c)
    end
    return off
end

"Set bits `first:first+count-1` (MSB-first) in a bitmap starting at 0-based byte `base`."
function setbits!(buf::Vector{UInt8}, first::Integer, count::Integer; base::Integer = 0)
    for b in first:(first + count - 1)
        buf[base + (b >> 3) + 1] |= 0x80 >> (b & 7)
    end
    return buf
end

function write_zeros(io::IO, n::Integer)
    chunk = zeros(UInt8, min(n, 4MiB))
    while n > 0
        k = min(n, length(chunk))
        write(io, k == length(chunk) ? chunk : zeros(UInt8, k))
        n -= k
    end
end

hfs_time(unix_seconds::Integer) = UInt32(unix_seconds + HFS_EPOCH)

function local_utc_offset()
    ms = Dates.value(Dates.now() - Dates.now(Dates.UTC))
    return 60 * round(Int, ms / 60_000)      # seconds, rounded to whole minutes
end

function device_size(path::AbstractString)
    ispath(path) || error("$path does not exist. Create it with the desired size first, " *
                          "e.g. `truncate -s 100M $path`.")
    isfile(path) && return filesize(path)
    return open(path, "r") do io     # block device
        seekend(io)
        position(io)
    end
end

function encode_volname(name::AbstractString)
    isempty(name) && error("volume name must not be empty")
    # HFS+ stores names as decomposed UTF-16; a POSIX ':' is stored as '/'.
    s = replace(normalize(String(name), :NFD), ':' => '/')
    u = transcode(UInt16, s)
    length(u) <= 255 || error("volume name is too long (max 255 UTF-16 units)")
    return u
end

# Apple's CalcHFSPlusBTreeClumpSize
function btree_clump_size(sectors::Integer, column::Integer, nodesize::Integer, blocksize::Integer)
    if sectors < 0x200000                     # < 1 GB: 0.8% of the volume
        clump = max(sectors << 2, 8 * nodesize)
    else
        i = 0
        s = sectors >> 22
        while s != 0 && i < length(CLUMP_TABLE) - 1
            i += 1
            s >>= 1
        end
        clump = CLUMP_TABLE[i + 1][column] * MiB
    end
    m = max(nodesize, blocksize)
    clump = (clump ÷ m) * m
    return clump == 0 ? m : clump
end

function default_blocksize(size::Integer)
    bs = size >= 2TiB ? 8192 : 4096
    while size ÷ bs > typemax(UInt32)
        bs *= 2
    end
    return bs
end

# ---------------------------------------------------------------------------
# On-disk structures
# ---------------------------------------------------------------------------

"B-tree header node (node 0): descriptor, BTHeaderRec, user data record, map record."
function btree_header_node(nodesize, totalnodes, clumpsize;
                           maxkeylen, attributes, keycompare = 0x00,
                           depth = 0, root = 0, leafrecords = 0,
                           firstleaf = 0, lastleaf = 0, usednodes = 1)
    mapbits = 8 * (nodesize - 256)
    totalnodes <= mapbits ||
        error("B-tree with $totalnodes nodes needs map nodes, which are not implemented")

    node = zeros(UInt8, nodesize)
    o = 0
    # BTNodeDescriptor
    o = wbe!(node, o, UInt32(0))               # fLink
    o = wbe!(node, o, UInt32(0))               # bLink
    o = wbe!(node, o, UInt8(1))                # kind = kBTHeaderNode
    o = wbe!(node, o, UInt8(0))                # height
    o = wbe!(node, o, UInt16(3))               # numRecords
    o = wbe!(node, o, UInt16(0))               # reserved
    # BTHeaderRec
    o = wbe!(node, o, UInt16(depth))           # treeDepth
    o = wbe!(node, o, UInt32(root))            # rootNode
    o = wbe!(node, o, UInt32(leafrecords))     # leafRecords
    o = wbe!(node, o, UInt32(firstleaf))       # firstLeafNode
    o = wbe!(node, o, UInt32(lastleaf))        # lastLeafNode
    o = wbe!(node, o, UInt16(nodesize))        # nodeSize
    o = wbe!(node, o, UInt16(maxkeylen))       # maxKeyLength
    o = wbe!(node, o, UInt32(totalnodes))      # totalNodes
    o = wbe!(node, o, UInt32(totalnodes - usednodes))  # freeNodes
    o = wbe!(node, o, UInt16(0))               # reserved1
    o = wbe!(node, o, UInt32(clumpsize))       # clumpSize
    o = wbe!(node, o, UInt8(0))                # btreeType = kHFSBTreeType
    o = wbe!(node, o, UInt8(keycompare))       # keyCompareType
    o = wbe!(node, o, UInt32(attributes))      # attributes
    # reserved3[16] (64 bytes) and the 128-byte user data record stay zero.
    # Map record at 248: one bit per node in use.
    setbits!(node, 0, usednodes; base = 248)
    # Record offsets, stored backwards from the end of the node
    wbe!(node, nodesize - 2, UInt16(14))            # header record
    wbe!(node, nodesize - 4, UInt16(120))           # user data record
    wbe!(node, nodesize - 6, UInt16(248))           # map record
    wbe!(node, nodesize - 8, UInt16(nodesize - 8))  # free space
    return node
end

"Catalog leaf node 1: root folder record and root folder thread record."
function catalog_root_leaf(nodesize, name::Vector{UInt16}, date::UInt32)
    node = zeros(UInt8, nodesize)
    n = length(name)
    o = 0
    # BTNodeDescriptor
    o = wbe!(node, o, UInt32(0))               # fLink
    o = wbe!(node, o, UInt32(0))               # bLink
    o = wbe!(node, o, 0xff)                    # kind = kBTLeafNode (-1)
    o = wbe!(node, o, UInt8(1))                # height
    o = wbe!(node, o, UInt16(2))               # numRecords
    o = wbe!(node, o, UInt16(0))               # reserved

    # Record 0 -- key (parentID = kHFSRootParentID, name = volume name)
    rec0 = o
    o = wbe!(node, o, UInt16(6 + 2n))          # keyLength
    o = wbe!(node, o, UInt32(1))               # parentID
    o = wunistr!(node, o, name)
    # HFSPlusCatalogFolder (88 bytes)
    o = wbe!(node, o, UInt16(1))               # recordType = kHFSPlusFolderRecord
    o = wbe!(node, o, UInt16(0))               # flags
    o = wbe!(node, o, UInt32(0))               # valence
    o = wbe!(node, o, UInt32(2))               # folderID = kHFSRootFolderID
    o = wbe!(node, o, date)                    # createDate
    o = wbe!(node, o, date)                    # contentModDate
    o += 68   # attributeModDate, accessDate, backupDate, permissions, userInfo,
              # finderInfo, textEncoding, reserved: all zero (as hfsprogs does)

    # Record 1 -- key (parentID = kHFSRootFolderID, empty name)
    rec1 = o
    o = wbe!(node, o, UInt16(6))               # keyLength
    o = wbe!(node, o, UInt32(2))               # parentID
    o = wbe!(node, o, UInt16(0))               # name length
    # HFSPlusCatalogThread
    o = wbe!(node, o, UInt16(3))               # recordType = kHFSPlusFolderThreadRecord
    o = wbe!(node, o, UInt16(0))               # reserved
    o = wbe!(node, o, UInt32(1))               # parentID
    o = wunistr!(node, o, name)

    wbe!(node, nodesize - 2, UInt16(rec0))
    wbe!(node, nodesize - 4, UInt16(rec1))
    wbe!(node, nodesize - 6, UInt16(o))        # free space
    return node
end

const EMPTY_FORK = (start = 0, blocks = 0, clump = 0)

function volume_header(; blocksize, totalblocks, freeblocks, nextalloc,
                       createdate, now, uuid, forks,
                       filecount = 0, foldercount = 0, nextcnid = 16)
    h = zeros(UInt8, 512)
    o = 0
    o = wbe!(h, o, 0x482B)                     # signature 'H+'
    o = wbe!(h, o, UInt16(4))                  # version
    o = wbe!(h, o, 0x80000100)                 # attributes: unmounted | unused-node-fix
    o = wbe!(h, o, 0x31302E30)                 # lastMountedVersion '10.0'
    o = wbe!(h, o, UInt32(0))                  # journalInfoBlock
    o = wbe!(h, o, createdate)                 # createDate (local time)
    o = wbe!(h, o, now)                        # modifyDate
    o = wbe!(h, o, UInt32(0))                  # backupDate
    o = wbe!(h, o, now)                        # checkedDate
    o = wbe!(h, o, UInt32(filecount))          # fileCount
    o = wbe!(h, o, UInt32(foldercount))        # folderCount (root not counted)
    o = wbe!(h, o, UInt32(blocksize))          # blockSize
    o = wbe!(h, o, UInt32(totalblocks))        # totalBlocks
    o = wbe!(h, o, UInt32(freeblocks))         # freeBlocks
    o = wbe!(h, o, UInt32(nextalloc))          # nextAllocation
    fork_clump = UInt32(max(blocksize, min(16 * blocksize, 65536)))
    o = wbe!(h, o, fork_clump)                 # rsrcClumpSize
    o = wbe!(h, o, fork_clump)                 # dataClumpSize
    o = wbe!(h, o, UInt32(nextcnid))           # nextCatalogID
    o = wbe!(h, o, UInt32(0))                  # writeCount
    o = wbe!(h, o, UInt64(1))                  # encodingsBitmap (MacRoman)
    o += 24                                    # finderInfo[0:5]
    o = wbe!(h, o, uuid[1])                    # finderInfo[6:7] = volume UUID
    o = wbe!(h, o, uuid[2])
    @assert o == 112
    # allocation, extents, catalog, attributes, startup (HFSPlusForkData, 80 bytes each)
    for f in forks
        o = wbe!(h, o, UInt64(f.blocks) * UInt64(blocksize))  # logicalSize
        o = wbe!(h, o, UInt32(f.clump))                       # clumpSize
        o = wbe!(h, o, UInt32(f.blocks))                      # totalBlocks
        o = wbe!(h, o, UInt32(f.start))                       # extents[0].startBlock
        o = wbe!(h, o, UInt32(f.blocks))                      # extents[0].blockCount
        o += 56                                               # extents[1:7]
    end
    @assert o == 512
    return h
end

function write_btree(io::IO, offset::Integer, filebytes::Integer, nodes)
    seek(io, offset)
    for node in nodes
        write(io, node)
    end
    write_zeros(io, filebytes - sum(length, nodes))
end

# ---------------------------------------------------------------------------
# Formatter
# ---------------------------------------------------------------------------

"""
    newfs_hfs(path; volname = "untitled", blocksize = nothing)

Format the existing file (or block device) at `path` as an empty HFS+ volume
named `volname`, equivalent to `newfs_hfs -v volname path`. The file is
formatted in place, so it must already have the desired size.
"""
function newfs_hfs(path::AbstractString; volname::AbstractString = "untitled",
                   blocksize::Union{Nothing,Integer} = nothing)
    size = (device_size(path) ÷ 512) * 512     # work in whole 512-byte sectors
    name = encode_volname(volname)

    bs = something(blocksize, default_blocksize(size))
    (ispow2(bs) && bs >= 512) || error("block size must be a power of two ≥ 512, got $bs")
    total = size ÷ bs
    total <= typemax(UInt32) || error("block size $bs is too small for a $size byte volume")
    sectors = size ÷ 512

    cat_node = sectors < 0x200000 ? 4096 : 8192

    ext_clump  = btree_clump_size(sectors, EXT_COL,  EXT_NODE_SIZE,  bs)
    attr_clump = btree_clump_size(sectors, ATTR_COL, ATTR_NODE_SIZE, bs)
    cat_clump  = btree_clump_size(sectors, CAT_COL,  cat_node,       bs)
    ext_blocks, attr_blocks, cat_blocks = ext_clump ÷ bs, attr_clump ÷ bs, cat_clump ÷ bs

    # Layout: [boot blocks + header] [bitmap] [extents] [attributes] (gap) [catalog] ... [alt header]
    hdr_blocks   = cld(1536, bs)
    alloc_start  = hdr_blocks
    alloc_blocks = cld(cld(total, 8), bs)
    ext_start    = alloc_start + alloc_blocks
    attr_start   = ext_start + ext_blocks
    # Alternate header sits 1024 bytes before the end; the last block is always reserved.
    tail_start   = min((size - 1024) ÷ bs, total - 1)
    gap          = size >= 2MiB ? 10 * attr_blocks : 0   # room for the attributes file to grow
    cat_start    = attr_start + attr_blocks + gap
    if cat_start + cat_blocks > tail_start && gap > 0
        cat_start -= gap
    end
    cat_end = cat_start + cat_blocks
    cat_end <= tail_start || error("$path ($size bytes) is too small for an HFS+ volume")

    tail_blocks = total - tail_start
    used = hdr_blocks + alloc_blocks + ext_blocks + attr_blocks + cat_blocks + tail_blocks

    # nextAllocation is only a hint; leave the catalog room to grow contiguously.
    extra = size >= 16GiB ? min(size * 5 ÷ 1024, 512MiB) ÷ bs : 0
    nextalloc = cat_end + 10 * cat_blocks + extra
    nextalloc < tail_start || (nextalloc = cat_end)

    # Allocation bitmap
    bitmap = zeros(UInt8, alloc_blocks * bs)
    setbits!(bitmap, 0, hdr_blocks)
    setbits!(bitmap, alloc_start, alloc_blocks)
    setbits!(bitmap, ext_start, ext_blocks)
    setbits!(bitmap, attr_start, attr_blocks)
    setbits!(bitmap, cat_start, cat_blocks)
    setbits!(bitmap, tail_start, tail_blocks)

    # Dates and volume UUID
    unix_now = floor(Int, time())
    now = hfs_time(unix_now)
    createdate = hfs_time(unix_now + local_utc_offset())
    uuid = check_uuid(generate_uuid())

    # B-trees
    ext_hdr = btree_header_node(EXT_NODE_SIZE, ext_clump ÷ EXT_NODE_SIZE, ext_clump;
                                maxkeylen = 10, attributes = 0x02)          # kBTBigKeysMask
    attr_hdr = btree_header_node(ATTR_NODE_SIZE, attr_clump ÷ ATTR_NODE_SIZE, attr_clump;
                                 maxkeylen = 266, attributes = 0x06)        # BigKeys | VariableIndexKeys
    cat_hdr = btree_header_node(cat_node, cat_clump ÷ cat_node, cat_clump;
                                maxkeylen = 516, attributes = 0x06,
                                keycompare = 0xCF,                          # kHFSCaseFolding
                                depth = 1, root = 1, leafrecords = 2,
                                firstleaf = 1, lastleaf = 1, usednodes = 2)
    cat_leaf = catalog_root_leaf(cat_node, name, now)

    header = volume_header(; blocksize = bs, totalblocks = total, freeblocks = total - used,
                           nextalloc = nextalloc, createdate = createdate, now = now, uuid = uuid,
                           forks = ((start = alloc_start, blocks = alloc_blocks, clump = alloc_blocks * bs),
                                    (start = ext_start,   blocks = ext_blocks,   clump = ext_clump),
                                    (start = cat_start,   blocks = cat_blocks,   clump = cat_clump),
                                    (start = attr_start,  blocks = attr_blocks,  clump = attr_clump),
                                    EMPTY_FORK))

    open(path, "r+") do io
        seek(io, 0)
        write_zeros(io, 1024)                          # boot blocks
        write(io, header)                              # primary volume header
        seek(io, alloc_start * bs)
        write(io, bitmap)
        write_btree(io, ext_start * bs,  ext_blocks * bs,  (ext_hdr,))
        write_btree(io, attr_start * bs, attr_blocks * bs, (attr_hdr,))
        write_btree(io, cat_start * bs,  cat_blocks * bs,  (cat_hdr, cat_leaf))
        seek(io, size - 1024)
        write(io, header)                              # alternate volume header
        write_zeros(io, 512)                           # reserved last sector
    end
    return path
end

# ---------------------------------------------------------------------------
# Catalog names: decomposition and case-insensitive ordering
# ---------------------------------------------------------------------------

# HFS+ orders catalog keys with Apple's FastUnicodeCompare (TN1150): every UTF-16
# unit is folded through a fixed table, folded zeros are skipped, and the results
# are compared as unsigned numbers. The table is the Unicode 2.0 lower-case mapping
# restricted to characters without a canonical decomposition (decomposable ones
# never occur, since names are stored decomposed), with NUL sorted last and a few
# format characters ignored. It is frozen: it must NOT follow newer Unicode data,
# which is why it isn't derived from `lowercase`. Runs are (first, last, stride, delta).
const FOLD_RUNS = (
    (0x0041, 0x005A, 1,  32), (0x00C6, 0x00C6, 1,  32), (0x00D0, 0x00D0, 1,  32),
    (0x00D8, 0x00D8, 1,  32), (0x00DE, 0x00DE, 1,  32), (0x0110, 0x0110, 1,   1),
    (0x0126, 0x0126, 1,   1), (0x0132, 0x0132, 1,   1), (0x013F, 0x0141, 2,   1),
    (0x014A, 0x014A, 1,   1), (0x0152, 0x0152, 1,   1), (0x0166, 0x0166, 1,   1),
    (0x0181, 0x0181, 1, 210), (0x0182, 0x0184, 2,   1), (0x0186, 0x0186, 1, 206),
    (0x0187, 0x0187, 1,   1), (0x0189, 0x018A, 1, 205), (0x018B, 0x018B, 1,   1),
    (0x018E, 0x018E, 1,  79), (0x018F, 0x018F, 1, 202), (0x0190, 0x0190, 1, 203),
    (0x0191, 0x0191, 1,   1), (0x0193, 0x0193, 1, 205), (0x0194, 0x0194, 1, 207),
    (0x0196, 0x0196, 1, 211), (0x0197, 0x0197, 1, 209), (0x0198, 0x0198, 1,   1),
    (0x019C, 0x019C, 1, 211), (0x019D, 0x019D, 1, 213), (0x019F, 0x019F, 1, 214),
    (0x01A2, 0x01A4, 2,   1), (0x01A7, 0x01A7, 1,   1), (0x01A9, 0x01A9, 1, 218),
    (0x01AC, 0x01AC, 1,   1), (0x01AE, 0x01AE, 1, 218), (0x01B1, 0x01B2, 1, 217),
    (0x01B3, 0x01B5, 2,   1), (0x01B7, 0x01B7, 1, 219), (0x01B8, 0x01B8, 1,   1),
    (0x01BC, 0x01BC, 1,   1), (0x01C4, 0x01C4, 1,   2), (0x01C5, 0x01C5, 1,   1),
    (0x01C7, 0x01C7, 1,   2), (0x01C8, 0x01C8, 1,   1), (0x01CA, 0x01CA, 1,   2),
    (0x01CB, 0x01CB, 1,   1), (0x01E4, 0x01E4, 1,   1), (0x01F1, 0x01F1, 1,   2),
    (0x01F2, 0x01F2, 1,   1), (0x0391, 0x03A1, 1,  32), (0x03A3, 0x03A9, 1,  32),
    (0x03E2, 0x03EE, 2,   1), (0x0402, 0x0404, 2,  80), (0x0405, 0x0406, 1,  80),
    (0x0408, 0x040B, 1,  80), (0x040F, 0x040F, 1,  80), (0x0410, 0x0418, 1,  32),
    (0x041A, 0x042F, 1,  32), (0x0460, 0x0474, 2,   1), (0x0478, 0x0480, 2,   1),
    (0x0490, 0x04BE, 2,   1), (0x04C3, 0x04C3, 1,   1), (0x04C7, 0x04C7, 1,   1),
    (0x04CB, 0x04CB, 1,   1), (0x0531, 0x0556, 1,  48), (0x10A0, 0x10C5, 1,  48),
    (0x2160, 0x216F, 1,  16), (0xFF21, 0xFF3A, 1,  32),
)
const FOLD_IGNORED = (0x200C:0x200F, 0x202A:0x202E, 0x206A:0x206F, 0xFEFF:0xFEFF)

function build_fold_table()
    t = collect(UInt16, 0x0000:0xFFFF)
    t[1] = 0xFFFF                                   # NUL sorts after everything
    for (a, b, s, d) in FOLD_RUNS, c in Int(a):s:Int(b)
        t[c + 1] = c + d
    end
    for r in FOLD_IGNORED, c in r
        t[Int(c) + 1] = 0x0000
    end
    return t
end
const FOLD_TABLE = build_fold_table()

"Case-folded name with ignorable characters removed; ordering these = FastUnicodeCompare."
function hfs_fold(name::Vector{UInt16})
    out = UInt16[]
    for c in name
        f = FOLD_TABLE[Int(c) + 1]
        f == 0x0000 || push!(out, f)
    end
    return out
end

# Apple's decomposition leaves these ranges composed (TN1150).
keep_composed(c::Char) = ('\u2000' <= c <= '\u2FFF') || ('\uF900' <= c <= '\uFAFF') ||
                         ('\U2F800' <= c <= '\U2FAFF')

"Convert a POSIX file name to its HFS+ catalog form (decomposed UTF-16, ':' stored as '/')."
function hfs_name(s::AbstractString)
    str = String(s)
    isvalid(str) || error("file name is not valid UTF-8: $(repr(str))")
    isempty(str) && error("empty file name")
    out, run = IOBuffer(), IOBuffer()
    for c in str
        if keep_composed(c)
            print(out, normalize(String(take!(run)), :NFD), c)
        else
            print(run, c)
        end
    end
    print(out, normalize(String(take!(run)), :NFD))
    u = transcode(UInt16, replace(String(take!(out)), ':' => '/'))
    length(u) <= 255 || error("name is longer than 255 UTF-16 units: $(repr(str))")
    return u
end

# ---------------------------------------------------------------------------
# Catalog records
# ---------------------------------------------------------------------------

const S_IFMT  = 0o170000
const S_IFDIR = 0o040000
const S_IFLNK = 0o120000

# macOS's HFS+ driver reports anything before 1970 as the Unix epoch, so clamp there
# (rather than storing a date that other readers would show differently); HFS+ ends in 2040.
hfs_date(t::Real) = UInt32(clamp(floor(Int, t), 0, typemax(UInt32) - HFS_EPOCH) + HFS_EPOCH)

"HFSPlusCatalogKey: keyLength, parentID, nodeName."
function catalog_key(parent::UInt32, name::Vector{UInt16})
    k = zeros(UInt8, 8 + 2 * length(name))
    o = wbe!(k, 0, UInt16(6 + 2 * length(name)))
    o = wbe!(k, o, parent)
    wunistr!(k, o, name)
    return k
end

# createDate, contentModDate, attributeModDate, accessDate, backupDate, then HFSPlusBSDInfo.
# All dates come from one value (the item's mtime or the forced timestamp): birth time,
# ctime and atime can't be reproduced, so using them would make images unreproducible.
function write_dates_and_bsd!(r, o, date::UInt32, mode, uid, gid)
    o = wbe!(r, o, date)                       # createDate
    o = wbe!(r, o, date)                       # contentModDate
    o = wbe!(r, o, date)                       # attributeModDate
    o = wbe!(r, o, date)                       # accessDate
    o = wbe!(r, o, UInt32(0))                  # backupDate
    o = wbe!(r, o, UInt32(uid))                # ownerID
    o = wbe!(r, o, UInt32(gid))                # groupID
    o = wbe!(r, o, UInt8(0))                   # adminFlags
    o = wbe!(r, o, UInt8(0))                   # ownerFlags
    o = wbe!(r, o, UInt16(mode & 0xffff))      # fileMode (type + permission bits)
    o = wbe!(r, o, UInt32(0))                  # special
    return o
end

"HFSPlusCatalogFolder (88 bytes)."
function folder_record(cnid, valence, date, mode, uid, gid)
    r = zeros(UInt8, 88)
    o = wbe!(r, 0, UInt16(1))                  # kHFSPlusFolderRecord
    o = wbe!(r, o, UInt16(0))                  # flags
    o = wbe!(r, o, UInt32(valence))
    o = wbe!(r, o, UInt32(cnid))
    write_dates_and_bsd!(r, o, date, mode, uid, gid)   # rest: FolderInfo, ExtendedFolderInfo, textEncoding = 0
    return r
end

"HFSPlusCatalogFile (248 bytes) with a single-extent data fork."
function file_record(cnid, date, mode, uid, gid, logical_size, start_block, nblocks; symlink = false)
    r = zeros(UInt8, 248)
    o = wbe!(r, 0, UInt16(2))                  # kHFSPlusFileRecord
    o = wbe!(r, o, UInt16(0x0002))             # flags = kHFSThreadExistsMask
    o = wbe!(r, o, UInt32(0))                  # reserved1
    o = wbe!(r, o, UInt32(cnid))
    o = write_dates_and_bsd!(r, o, date, mode, uid, gid)
    # FileInfo: symbolic links are type 'slnk', creator 'rhap'
    o = wbe!(r, o, symlink ? 0x736C6E6B : 0x00000000)
    o = wbe!(r, o, symlink ? 0x72686170 : 0x00000000)
    o += 8                                     # finderFlags, location, reservedField
    o += 16                                    # ExtendedFileInfo
    o += 8                                     # textEncoding, reserved2
    # dataFork
    o = wbe!(r, o, UInt64(logical_size))
    o = wbe!(r, o, UInt32(0))                  # clumpSize
    o = wbe!(r, o, UInt32(nblocks))            # totalBlocks
    o = wbe!(r, o, UInt32(nblocks > 0 ? start_block : 0))
    o = wbe!(r, o, UInt32(nblocks))
    # remaining extents and the resource fork stay zero
    return r
end

"HFSPlusCatalogThread: 3 = folder thread, 4 = file thread."
function thread_record(rectype, parent::UInt32, name::Vector{UInt16})
    r = zeros(UInt8, 10 + 2 * length(name))
    o = wbe!(r, 0, UInt16(rectype))
    o = wbe!(r, o, UInt16(0))
    o = wbe!(r, o, parent)
    wunistr!(r, o, name)
    return r
end

# ---------------------------------------------------------------------------
# B-tree construction (bottom-up from sorted records)
# ---------------------------------------------------------------------------

"Split records into consecutive groups that each fit into one node."
function pack_records(recs::Vector{Vector{UInt8}}, nodesize)
    groups = Vector{Vector{Int}}()
    current = Int[]
    used = 14 + 2                                    # descriptor + free-space offset
    for (i, r) in enumerate(recs)
        need = length(r) + 2                         # record + its offset slot
        if !isempty(current) && used + need > nodesize
            push!(groups, current)
            current, used = Int[], 16
        end
        used + need <= nodesize || error("catalog record does not fit into a node")
        push!(current, i)
        used += need
    end
    isempty(current) || push!(groups, current)
    return groups
end

function btree_node(kind::UInt8, height, recs, flink, blink, nodesize)
    node = zeros(UInt8, nodesize)
    o = wbe!(node, 0, UInt32(flink))
    o = wbe!(node, o, UInt32(blink))
    o = wbe!(node, o, kind)
    o = wbe!(node, o, UInt8(height))
    o = wbe!(node, o, UInt16(length(recs)))
    o = wbe!(node, o, UInt16(0))
    for (i, r) in enumerate(recs)
        wbe!(node, nodesize - 2i, UInt16(o))
        copyto!(node, o + 1, r, 1, length(r))
        o += length(r)
    end
    wbe!(node, nodesize - 2 * (length(recs) + 1), UInt16(o))   # free space
    return node
end

"""
Build catalog nodes 1..N from sorted (key, key*data) pairs: packed leaves, then index
levels (variable-length keys) until a single root remains.
Returns (nodes, root, depth, nleaves).
"""
function build_catalog_tree(keys::Vector{Vector{UInt8}}, recs::Vector{Vector{UInt8}}, nodesize)
    nodes = Vector{Vector{UInt8}}()
    groups = pack_records(recs, nodesize)
    nleaves = length(groups)
    level = Tuple{Vector{UInt8},Int}[]               # (first key, node number)
    for (k, g) in enumerate(groups)
        push!(nodes, btree_node(0xff, 1, recs[g], k < nleaves ? k + 1 : 0, k > 1 ? k - 1 : 0, nodesize))
        push!(level, (keys[g[1]], k))
    end
    height = 1
    while length(level) > 1
        height += 1
        irecs = [vcat(key, reinterpret(UInt8, [hton(UInt32(num))])) for (key, num) in level]
        groups = pack_records(irecs, nodesize)
        base = length(nodes)
        next = Tuple{Vector{UInt8},Int}[]
        for (k, g) in enumerate(groups)
            num = base + k
            push!(nodes, btree_node(0x00, height, irecs[g], k < length(groups) ? num + 1 : 0,
                                    k > 1 ? num - 1 : 0, nodesize))
            push!(next, (level[g[1]][1], num))
        end
        level = next
    end
    return nodes, level[1][2], height, nleaves
end

# ---------------------------------------------------------------------------
# Staging directory scan
# ---------------------------------------------------------------------------

mutable struct StageItem
    path::String
    kind::Symbol                       # :dir, :file or :link
    cnid::UInt32
    parent::UInt32
    name::Vector{UInt16}
    st::Base.Filesystem.StatStruct
    valence::Int                       # number of children (folders)
    size::Int                          # data fork length (files, links)
    start::Int                         # first block, relative to the data area
    target::Vector{UInt8}              # symlink target
end

function scan_stage!(items, dir, parent::UInt32, nextid::Ref{UInt32})
    count = 0
    for n in readdir(dir)                            # sorted: deterministic layout
        p = joinpath(dir, n)
        st = lstat(p)
        kind = islink(st) ? :link : isdir(st) ? :dir : isfile(st) ? :file : :other
        if kind === :other
            @warn "Skipping $p: sockets, FIFOs and device files are not supported"
            continue
        end
        cnid = nextid[]
        nextid[] += 1
        item = StageItem(p, kind, cnid, parent, hfs_name(n), st, 0, 0, 0, UInt8[])
        push!(items, item)
        count += 1
        kind === :dir && (item.valence = scan_stage!(items, p, cnid, nextid))
    end
    return count
end

function copy_file_into(dst::IOStream, src::AbstractString, n::Integer, buf::Vector{UInt8})
    open(src, "r") do io
        remaining = n
        while remaining > 0
            k = readbytes!(io, buf, min(remaining, length(buf)))
            k == 0 && error("$src changed size while building the image")
            unsafe_write(dst, pointer(buf), k)
            remaining -= k
        end
        eof(io) || error("$src changed size while building the image")
    end
end

# ---------------------------------------------------------------------------
# Reproducibility helpers
# ---------------------------------------------------------------------------

"""
    generate_uuid() -> UInt64

Random volume identifier for `build_hfs`. HFS+ stores a 64-bit identifier (Finder
info words 6-7 of the volume header); macOS derives the 128-bit "Volume UUID" shown
by `diskutil` from it. Zero means "no identifier" to macOS and is never returned.
"""
function generate_uuid()
    u = rand(RandomDevice(), UInt64)
    return u == 0 ? generate_uuid() : u
end

function check_uuid(uuid::Integer)
    0 < uuid <= typemax(UInt64) ||
        error("uuid must be a non-zero 64-bit unsigned integer (HFS+ stores 64 bits), got $uuid")
    u = UInt64(uuid)
    return (UInt32(u >> 32), UInt32(u & 0xffffffff))
end

unix_time(t::Real) = t
unix_time(t::Dates.DateTime) = Dates.datetime2unix(t)       # DateTime is taken as UTC

# ---------------------------------------------------------------------------
# One-pass image builder
# ---------------------------------------------------------------------------

"""
    build_hfs(stage, img; volname = "untitled", free_space = 0, blocksize = 4096,
              uid = 99, gid = 99, timestamp = nothing, uuid = generate_uuid())

Create `img` as an HFS+ volume containing the contents of the directory `stage`
(replaces `newfs_hfs` + `hfsplus img addall stage`). The image is sized to fit
exactly, plus `free_space` bytes. Every file is stored contiguously; permission
bits and modification times (whole seconds) are preserved, symlinks are kept as
symlinks, hard links become separate copies. Owners are set to `uid`/`gid`
(99 = "unknown", which macOS maps to the current user).

Names that differ only by case (or by Unicode normalization) within one folder
are rejected, since HFS+ is case-insensitive.

Reproducibility: `timestamp` (Unix seconds or a UTC `DateTime`) forces the dates of
every file, folder and link, and of the volume itself; with `nothing` each item keeps
its own mtime and the volume gets the newest one. `uuid` is the 64-bit volume
identifier, the only random part of an image (see `generate_uuid`). Given the same
stage contents, mtimes (or `timestamp`) and `uuid`, the image is byte-for-byte identical.
Times before 1970 are stored as 1970 (macOS can't show earlier ones); HFS+ ends in 2040.
"""
function build_hfs(stage::AbstractString, img::AbstractString; volname::AbstractString = "untitled",
                   free_space::Integer = 0, blocksize::Integer = 4096, uid::Integer = 99, gid::Integer = 99,
                   timestamp::Union{Nothing,Real,Dates.DateTime} = nothing,
                   uuid::Integer = generate_uuid())
    isdir(stage) || error("$stage is not a directory")
    forced = timestamp === nothing ? nothing : unix_time(timestamp)
    datefor(st) = hfs_date(forced === nothing ? st.mtime : forced)
    uuid_words = check_uuid(uuid)
    bs = Int(blocksize)
    (ispow2(bs) && bs >= 512) || error("block size must be a power of two ≥ 512, got $bs")
    vname = hfs_name(volname)
    rootst = stat(stage)

    # --- Scan the stage and assign catalog node IDs (root folder = 2, user items from 16)
    items = StageItem[]
    nextid = Ref{UInt32}(16)
    root_valence = scan_stage!(items, stage, UInt32(2), nextid)

    # --- Place file data contiguously, relative to the start of the data area
    data_blocks = 0
    for it in items
        it.kind === :dir && continue
        if it.kind === :link
            it.target = Vector{UInt8}(readlink(it.path))
            it.size = length(it.target)
        else
            it.size = it.st.size
        end
        it.start = data_blocks
        data_blocks += cld(it.size, bs)
    end

    # --- Build and sort catalog records; the data area start isn't known yet, so file
    #     records are built after sizing. Collect sort keys first to detect collisions.
    cat_node = 8192
    entries = Tuple{UInt32,Vector{UInt16},Int}[]     # (parent, folded name, item index; 0 = root)
    push!(entries, (UInt32(1), hfs_fold(vname), 0))
    for (i, it) in enumerate(items)
        fold = hfs_fold(it.name)
        isempty(fold) && error("$(it.path): name consists only of characters HFS+ ignores")
        push!(entries, (it.parent, fold, i))
    end
    sort!(entries, by = e -> (e[1], e[2]))
    for k in 2:length(entries)
        a, b = entries[k - 1], entries[k]
        if a[1] == b[1] && a[2] == b[2]
            pa = a[3] == 0 ? "volume name" : items[a[3]].path
            pb = b[3] == 0 ? "volume name" : items[b[3]].path
            error("names collide on case-insensitive HFS+: $pa and $pb")
        end
    end

    function catalog_records(data_start)
        recs = Tuple{UInt32,Vector{UInt16},Vector{UInt8},Vector{UInt8}}[]   # parent, fold, key, record
        add!(parent, name, fold, data) = (k = catalog_key(parent, name); push!(recs, (parent, fold, k, vcat(k, data))))
        # Root folder and its thread
        add!(UInt32(1), vname, hfs_fold(vname), folder_record(2, root_valence, datefor(rootst), rootst.mode, uid, gid))
        add!(UInt32(2), UInt16[], UInt16[], thread_record(3, UInt32(1), vname))
        for it in items
            fold = hfs_fold(it.name)
            if it.kind === :dir
                add!(it.parent, it.name, fold, folder_record(it.cnid, it.valence, datefor(it.st), it.st.mode, uid, gid))
                add!(it.cnid, UInt16[], UInt16[], thread_record(3, it.parent, it.name))
            else
                n = cld(it.size, bs)
                add!(it.parent, it.name, fold, file_record(it.cnid, datefor(it.st), it.st.mode, uid, gid, it.size,
                                                           data_start + it.start, n;
                                                           symlink = it.kind === :link))
                add!(it.cnid, UInt16[], UInt16[], thread_record(4, it.parent, it.name))
            end
        end
        sort!(recs, by = r -> (r[1], r[2]))
        return [r[3] for r in recs], [r[4] for r in recs]
    end

    # Node count doesn't depend on block numbers, so size the tree with a dry run.
    dry_keys, dry_recs = catalog_records(0)
    ncat_nodes = length(build_catalog_tree(dry_keys, dry_recs, cat_node)[1])

    # --- Size the volume: B-tree clumps depend on the volume size, so iterate to a fixed point
    extra_blocks = cld(free_space, bs)
    tail_blocks = cld(1024, bs)                      # alternate header + reserved sector
    hdr_blocks = cld(1536, bs)
    total = data_blocks + extra_blocks + 64
    local ext_clump, attr_clump, cat_bytes, alloc_blocks, required
    while true
        sectors = total * bs ÷ 512
        ext_clump  = btree_clump_size(sectors, EXT_COL,  EXT_NODE_SIZE,  bs)
        attr_clump = btree_clump_size(sectors, ATTR_COL, ATTR_NODE_SIZE, bs)
        m = max(cat_node, bs)
        cat_bytes = max(btree_clump_size(sectors, CAT_COL, cat_node, bs),
                        cld((1 + ncat_nodes) * cat_node, m) * m)
        alloc_blocks = cld(cld(total, 8), bs)
        required = hdr_blocks + alloc_blocks + (ext_clump + attr_clump + cat_bytes) ÷ bs +
                   data_blocks + extra_blocks + tail_blocks
        required <= total && break
        total = required
    end
    total <= typemax(UInt32) || error("volume too large for block size $bs")
    size = total * bs

    ext_blocks, attr_blocks, cat_blocks = ext_clump ÷ bs, attr_clump ÷ bs, cat_bytes ÷ bs
    alloc_start = hdr_blocks
    ext_start   = alloc_start + alloc_blocks
    attr_start  = ext_start + ext_blocks
    cat_start   = attr_start + attr_blocks
    data_start  = cat_start + cat_blocks
    data_end    = data_start + data_blocks
    tail_start  = total - tail_blocks

    # --- Catalog B-tree with final block numbers
    keys, recs = catalog_records(data_start)
    cat_nodes, cat_root, cat_depth, nleaves = build_catalog_tree(keys, recs, cat_node)
    @assert length(cat_nodes) == ncat_nodes
    cat_total_nodes = cat_bytes ÷ cat_node
    cat_hdr = btree_header_node(cat_node, cat_total_nodes, cat_bytes;
                                maxkeylen = 516, attributes = 0x06, keycompare = 0xCF,
                                depth = cat_depth, root = cat_root, leafrecords = length(recs),
                                firstleaf = 1, lastleaf = nleaves, usednodes = 1 + ncat_nodes)
    ext_hdr = btree_header_node(EXT_NODE_SIZE, ext_clump ÷ EXT_NODE_SIZE, ext_clump;
                                maxkeylen = 10, attributes = 0x02)
    attr_hdr = btree_header_node(ATTR_NODE_SIZE, attr_clump ÷ ATTR_NODE_SIZE, attr_clump;
                                 maxkeylen = 266, attributes = 0x06)

    # --- Allocation bitmap
    bitmap = zeros(UInt8, alloc_blocks * bs)
    setbits!(bitmap, 0, data_end)                    # metadata + file data are contiguous
    setbits!(bitmap, tail_start, tail_blocks)
    used = data_end + tail_blocks

    # --- Volume header
    # Volume dates: the forced timestamp, else the newest item (not the build time),
    # so identical inputs give identical images.
    vdate = hfs_date(forced !== nothing ? forced :
                     reduce(max, (it.st.mtime for it in items); init = rootst.mtime))
    nfolders = count(it -> it.kind === :dir, items)
    header = volume_header(; blocksize = bs, totalblocks = total, freeblocks = total - used,
                           nextalloc = data_end < tail_start ? data_end : 0,
                           createdate = vdate, now = vdate, uuid = uuid_words,
                           filecount = length(items) - nfolders, foldercount = nfolders,
                           nextcnid = nextid[],
                           forks = ((start = alloc_start, blocks = alloc_blocks, clump = alloc_blocks * bs),
                                    (start = ext_start,   blocks = ext_blocks,   clump = ext_clump),
                                    (start = cat_start,   blocks = cat_blocks,   clump = cat_bytes),
                                    (start = attr_start,  blocks = attr_blocks,  clump = attr_clump),
                                    EMPTY_FORK))

    # --- Write everything
    open(img, "w") do io
        truncate(io, size)                           # sparse; unused space reads as zeros
        seek(io, 1024)
        write(io, header)
        seek(io, alloc_start * bs)
        write(io, bitmap)
        write_btree(io, ext_start * bs,  ext_blocks * bs,  (ext_hdr,))
        write_btree(io, attr_start * bs, attr_blocks * bs, (attr_hdr,))
        write_btree(io, cat_start * bs,  cat_blocks * bs,  vcat([cat_hdr], cat_nodes))
        buf = Vector{UInt8}(undef, 4MiB)
        for it in items
            (it.kind === :dir || it.size == 0) && continue
            seek(io, (data_start + it.start) * bs)
            if it.kind === :link
                write(io, it.target)
            else
                copy_file_into(io, it.path, it.size, buf)
            end
        end
        seek(io, size - 1024)
        write(io, header)
    end
    return img
end

end # module

