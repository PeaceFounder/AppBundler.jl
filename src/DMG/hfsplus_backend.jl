struct HFSPlusBackend <: ImageBackend
    slack::Float64
end

using libdmg_hfsplus_jll: dmg, hfsplus
using hfsprogs_jll: newfs_hfs
const hfsplus_cmd = hfsplus

# hfsplus_backend
"""
    remove_symlinks(target; inline=false, warn=true)

Recursively removes all symlinks from `target`.

If `inline=false`, all symlinks are removed.

If `inline=true`, symlinks to files are replaced with copies of their
targets. Inlining symlinks to directories is not supported and throws
an `ArgumentError`.

If `warn=true`, a warning is emitted for every symlink encountered.
"""
function remove_symlinks(target; inline=false, warn=true)
    for (root, dirs, files) in walkdir(target; follow_symlinks=false)
        # Directory symlinks
        for name in dirs
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)

                if !isabspath(link_target)
                    link_target = joinpath(root, link_target)
                end

                link_target = normpath(link_target)

                if inline
                    throw(ArgumentError(
                        "Inlining symlinked directories is not supported: " *
                        "$path -> $link_target"
                    ))
                end

                warn && @warn "Removing symlink" path target=link_target
                rm(path)
            end
        end

        # File symlinks
        for name in files
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)

                if !isabspath(link_target)
                    link_target = joinpath(root, link_target)
                end

                link_target = normpath(link_target)

                warn && @warn "Removing symlink" path target=link_target

                if inline
                    rm(path)
                    cp(link_target, path)
                else
                    rm(path)
                end
            end
        end
    end

    return nothing
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



function build_image(backend::HFSPlusBackend, stage, img; volume_name = "")
    #iso_stage = tempname() 

    symlinks = extract_symlinks(stage)
    #println("Forming hfs archive with hfsplus at $stage")
    du_blocks = parse(Int, split(strip(read(`du -s $stage`, String)))[1])

    # ~2% slack, following the original shell recipe.
    size = du_blocks ÷ 1000 * 102 ÷ 100 + 1
    
    run(`dd if=/dev/zero of=$img bs=1M count=$size`)
    run(`$(newfs_hfs()) -v $volume_name $img`)

    run(`$(hfsplus_cmd()) $img addall $stage`)

    for (path, link_target) in symlinks
        run(`$(hfsplus_cmd()) $img symlink $path $link_target`)
    end

    return
end

function compress_image(backend::HFSPlusBackend, img, destination; compression = :lzma)
    run(`$(dmg()) build $img $destination --compression=$compression`)
    #run(`$(dmg()) dmg $img $destination --compression=$compression`)
    return
end
