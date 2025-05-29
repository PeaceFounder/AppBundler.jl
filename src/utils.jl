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
            mkpath(dirname(outpath)) # Shouldn't be needed

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


function is_windows_compatible(filename::String; path_length_threshold)
    # Check for invalid characters

    if occursin(r"[<>:\"\\\|?*\x00-\x1F]", filename) || occursin(r"[\x7F-\x9F]", filename)
        @warn "$(filename) contains invalid characters for Windows."
        return false
    end
    # if occursin(r"[\\/:*?\"<>|]", filename)
    #     @warn "$filename contains invalid characters for Windows.\n"
    #     return false
    # end

    # Check for reserved names
    reserved_names = ["CON", "PRN", "AUX", "NUL"]
    reserved_names_with_numbers = [string(name, i) for name in ["COM", "LPT"] for i in 1:9]
    append!(reserved_names, reserved_names_with_numbers)

    basename_no_ext = splitext(basename(filename))[1]
    if uppercase(basename_no_ext) in reserved_names
        @warn "$filename is a reserved name in Windows.\n"
        return false
    end

    # # Check filename length (Windows max path is 260 characters)
    if length(filename) > path_length_threshold
        @warn "$filename exceeds Windows max path length.\n"
        return false
    end

    return true
end


function ensure_windows_compatability(src_dir::String; path_length_threshold::Int = 260, skip_long_paths::Bool = false)

    error_paths = []
    
    max_length = 0

    for (root, dirs, files) in walkdir(src_dir)
        for file in files
            filepath = joinpath(root, file)
            rel_path = relpath(filepath, src_dir)
            
            if skip_long_paths && length(rel_path) > path_length_threshold
                rm(filepath)
                continue
            end

            if !is_windows_compatible(rel_path; path_length_threshold)
                push!(error_paths, rel_path)
                #error("Aborting due to Windows-incompatible filename.")
            end

            if length(rel_path) > max_length
                max_length = length(rel_path)
            end
        end
    end

    # removing empty direcotories
    for (root, dirs, files) in walkdir(src_dir, topdown=false)
        for dir in dirs
            path = joinpath(root, dir)
            if isempty(readdir(path))
                rm(path)
            end
        end
    end

    @info "Maximum relative path length is $max_length"

    if length(error_paths) > 0
        #@warn "$(length(error_paths)) errors detected"
        error("$(length(error_paths)) errors detected")
    end

    return
end


function zip_directory(src_dir::AbstractString, output_zip::AbstractString; path_length_threshold::Int = 260, skip_long_paths::Bool = false)

    rm(output_zip, force=true, recursive=true)

    p7zip = p7zip_jll.p7zip()
    run(`$p7zip a $output_zip $src_dir/\*`)

    return
end


# import squashfs_tools_jll

# function squash_snap(source, destination)
    
#     if squashfs_tools_jll.is_available()    
#         mksquashfs = squashfs_tools_jll.mksquashfs()
#     else
#         @info "squashfs-tools not available from jll. Attempting to use mksquashfs from the system."
#         mksquashfs = "mksquashfs"
#     end

#     run(`$mksquashfs $source $destination -noappend -comp xz`)

#     return
# end

function linux_arch_triplet(arch::Symbol)

    if arch == :aarch64
        return "aarch64-linux-gnu"
    elseif arch == :x86_64
        return "x86_64-linux-gnu"
    elseif arch == :i686
        return "i386-linux-gnu"
    else
        error("Unuported arhitecture $arch")
    end

end

function ensure_track_content_fpath(file_path::AbstractString)

    function transform_dependency(match)
        e = Meta.parse(match)
        return "include_dependency($(e.args[2]), track_content=true)"
    end

    content = read(file_path, String)
    new_content = replace(content, r"include_dependency.*" => transform_dependency)
    
    if content != new_content

        chmod(file_path, 0o644)
        write(file_path, new_content)
        chmod(file_path, 0o444)
        @info "include_dependency updated $file_path"

    end
end


function ensure_track_content(dir_path::AbstractString)

    for (root, dirs, files) in walkdir(dir_path)
        for file in files
            if endswith(file, ".jl")
                file_path = joinpath(root, file)
                try
                    ensure_track_content_fpath(file_path)
                catch 
                    @info "include_dependency skipped $file_path"
                end
            end
        end
    end

    return
end



