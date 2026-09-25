"""
    NewfsHFS

Pure-Julia replacement for `newfs_hfs` / `mkfs.hfsplus` from hfsprogs.
Formats an existing file (or block device) as an empty, non-journaled HFS+
volume with the same layout hfsprogs 540.1 produces: allocation bitmap,
extents-overflow B-tree, attributes B-tree, catalog B-tree with the root
folder, and primary + alternate volume headers.

Library use:

    using .NewfsHFS
    run(`truncate -s 200M img_stage`)          # or: open(f -> truncate(f, 200*2^20), "img_stage", "w")
    newfs_hfs("img_stage"; volname = "volume name")

Command line (same calling convention as hfsprogs):

    julia NewfsHFS.jl -v "volume name" img_stage
"""
module NewfsHFS

using Dates: Dates
using Random: RandomDevice
using Unicode: normalize

export newfs_hfs

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
                       createdate, now, uuid, forks)
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
    o = wbe!(h, o, UInt32(0))                  # fileCount
    o = wbe!(h, o, UInt32(0))                  # folderCount
    o = wbe!(h, o, UInt32(blocksize))          # blockSize
    o = wbe!(h, o, UInt32(totalblocks))        # totalBlocks
    o = wbe!(h, o, UInt32(freeblocks))         # freeBlocks
    o = wbe!(h, o, UInt32(nextalloc))          # nextAllocation
    fork_clump = UInt32(max(blocksize, min(16 * blocksize, 65536)))
    o = wbe!(h, o, fork_clump)                 # rsrcClumpSize
    o = wbe!(h, o, fork_clump)                 # dataClumpSize
    o = wbe!(h, o, UInt32(16))                 # nextCatalogID = kHFSFirstUserCatalogNodeID
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
    rng = RandomDevice()
    uuid = (rand(rng, UInt32), rand(rng, UInt32))

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
                           nextalloc, createdate, now, uuid,
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


end # module
