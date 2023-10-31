using ZipFile
import p7zip_jll

using Tar
using CodecZlib

function isext(filename::String, ext::String)
    # Base case: if the filename is empty or doesn't have the extension, return false.
    if isempty(filename) || !endswith(filename, ext)
        return false
    end
    
    # If the current filename ends with the desired extension, return true.
    if endswith(filename, ext)
        return true
    end
    
    # Otherwise, recurse after stripping the current extension.
    root, _ = splitext(filename)
    return isext(root, ext)
end

function extract_tar_gz(archive_path::String)

    open(archive_path, "r") do io
        decompressed = GzipDecompressorStream(io)
        return Tar.extract(decompressed)
    end
end


function extract_zip(archive_path::String)

    zip = ZipFile.Reader(archive_path)

    output_directory = joinpath(tempdir(), "zip_archive")
    rm(output_directory, recursive=true, force=true)


    for entry in zip.files
        if entry.method == ZipFile.Store
            outpath = joinpath(output_directory, entry.name)
            mkpath(outpath)
        end
    end


    for entry in zip.files
        if entry.method == ZipFile.Deflate
            outpath = joinpath(output_directory, entry.name)

            open(outpath, "w") do out_file
                write(out_file, read(entry))
            end
        end
    end

    close(zip)

    return output_directory
end

function extract(archive::String)

    if isext(archive, ".tar.gz") 
        return extract_tar_gz(archive)
    elseif isext(archive, ".zip")
        return extract_zip(archive)
    else
        error("Can not extract $(basename(archive)) as extension is not implemented")
    end
end


function zip_directory(src_dir::AbstractString, output_zip::AbstractString)

    rm(output_zip, force=true, recursive=true)
    
    p7zip = p7zip_jll.p7zip()
    run(`$p7zip a $output_zip $src_dir/\*`)

    return
end


import squashfs_tools_jll

function squash_snap(source, destination)
    
    if squashfs_tools_jll.is_available()    
        mksquashfs = squashfs_tools_jll.mksquashfs()
    else
        @info "squashfs-tools not available from jll. Attempting to use mksquashfs from the system."
        mksquashfs = "mksquashfs"
    end

    run(`$mksquashfs $source $destination -noappend -comp xz`)

    return
end


