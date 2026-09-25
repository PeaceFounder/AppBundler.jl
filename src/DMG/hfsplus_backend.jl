using ..NewfsHFS: newfs_hfs
using libdmg_hfsplus_jll: dmg, hfsplus
#using hfsprogs_jll: newfs_hfs

struct HFSPlusBackend <: ImageBackend
    slack::Float64
end

"""
    extract_symlinks(target; warn=true)

Find all symlinks recursively below `target`, remove them, and return their
locations and original link targets.

The symlink path is relative to `target`. The target is preserved exactly
as returned by `readlink`, so relative symlink targets remain relative.
"""
function extract_symlinks(target; warn=true)
    target = abspath(target)
    symlinks = Tuple{String, String}[]

    for (root, dirs, files) in walkdir(target; follow_symlinks=false)
        for name in Iterators.flatten((dirs, files))
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)
                relative_path = relpath(path, target)

                warn && @warn "Extracting symlink" path=relative_path target=link_target

                push!(symlinks, (relative_path, link_target))
                rm(path)
            end
        end
    end

    return symlinks
end

"""
    disk_usage(path) -> Int

Bytes allocated on disk for `path` and everything below it, counted the way
`du` does: `lstat` block counts (symlinks are not followed), the root directory
itself is included, and hard-linked files are counted only once.
"""
function disk_usage(path)
    seen = Set{Tuple{UInt64, UInt64}}()
    total = 0
    entries = (joinpath(root, name) for (root, dirs, files) in walkdir(path)
                                    for name in Iterators.flatten((dirs, files)))
    for p in Iterators.flatten(((path,), entries))
        st = lstat(p)
        if !isdir(st) && st.nlink > 1
            key = (st.device, st.inode)
            key in seen && continue
            push!(seen, key)
        end
        total += st.blocks * 512
    end
    return total
end

"""
    du_s(path; blocksize = Sys.isapple() ? 512 : 1024) -> Int

Pure-Julia analogue of `du -s path`: the disk usage of `path` and everything
below it, in units of `blocksize` bytes, rounded up.

The default `blocksize` matches the native `du` on each platform: 512-byte
blocks on macOS and 1K blocks on Linux. See [`disk_usage`](@ref) for how
the usage is counted.

# Examples

Compare against the system `du`. The `-k` flag forces 1K blocks on both
macOS and Linux, so the check is platform-independent:

```julia
expected = parse(Int, first(split(read(`du -sk \$path`, String))))
@assert du_s(path; blocksize = 1024) == expected
```
"""
du_s(path; blocksize = Sys.isapple() ? 512 : 1024) = cld(disk_usage(path), blocksize)


"""
    allocate_image(path, nbytes)

Create a zero-filled image file of exactly `nbytes` bytes at `path`.
"""
function allocate_image(path, nbytes::Integer)
    nbytes >= 0 || throw(ArgumentError("Image size must be non-negative, got $nbytes"))
    open(io -> truncate(io, nbytes), path, "w")
    return path
end

function build_image(backend::HFSPlusBackend, stage, img; volume_name = "")

    symlinks = extract_symlinks(stage)

    MiB = 2^20
    nbytes = ceil(Int, disk_usage(stage) * (1 + backend.slack)) + MiB
    nbytes = cld(nbytes, MiB) * MiB
    allocate_image(img, nbytes)

    #run(`$(newfs_hfs()) -v $volume_name $img`)
    newfs_hfs(img; volname = volume_name)

    run(`$(hfsplus()) $img addall $stage`)

    for (path, link_target) in symlinks
        run(`$(hfsplus()) $img symlink $path $link_target`)
    end

    return
end

function compress_image(backend::HFSPlusBackend, img, destination; compression = :lzma)
    run(`$(dmg()) build $img $destination --compression=$compression`)
    return
end
