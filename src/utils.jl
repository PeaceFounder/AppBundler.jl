using Random: RandomDevice
using Base64
using rcodesign_jll: rcodesign

function generate_macos_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)
    
    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))
        
    destination = joinpath(root, "meta/macos/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="$person_name" --p12-file="$destination" --p12-password="$password" --country-name=$country --validity-days="$validity_days"`)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/macos/certificate.pfx; To use certificate set certificate password with environment variable:

        export MACOS_PFX_PASSWORD="$password"
    """)

    ENV["MACOS_PFX_PASSWORD"] = password

    return
end


function generate_windows_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)

    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))

    destination = joinpath(root, "meta/windows/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))
    
    MSIXPack.generate_self_signed_certificate(destination; password, name = person_name, country, validity_days)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/windows/certificate.pfx; To use certificate set certificate password with environment variable:

        export WINDOWS_PFX_PASSWORD="$password"
    """)
    
    ENV["WINDOWS_PFX_PASSWORD"] = password

    return
end


# using ZipFile
# import p7zip_jll

#using Tar
#using CodecZlib

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

# function extract_tar_gz(archive_path::String)

#     open(archive_path, "r") do io
#         decompressed = GzipDecompressorStream(io)
#         return Tar.extract(decompressed)
#     end
# end

# function linux_arch_triplet(arch::Symbol)

#     if arch == :aarch64
#         return "aarch64-linux-gnu"
#     elseif arch == :x86_64
#         return "x86_64-linux-gnu"
#     elseif arch == :i686
#         return "i386-linux-gnu"
#     else
#         error("Unuported arhitecture $arch")
#     end

# end

# function ensure_track_content_fpath(file_path::AbstractString)

#     function transform_dependency(match)
#         e = Meta.parse(match)
#         return "include_dependency($(e.args[2]), track_content=true)"
#     end

#     content = read(file_path, String)
#     new_content = replace(content, r"include_dependency.*" => transform_dependency)
    
#     if content != new_content

#         chmod(file_path, 0o644)
#         write(file_path, new_content)
#         chmod(file_path, 0o444)
#         @info "include_dependency updated $file_path"

#     end
# end


# function ensure_track_content(dir_path::AbstractString)

#     for (root, dirs, files) in walkdir(dir_path)
#         for file in files
#             if endswith(file, ".jl")
#                 file_path = joinpath(root, file)
#                 try
#                     ensure_track_content_fpath(file_path)
#                 catch 
#                     @info "include_dependency skipped $file_path"
#                 end
#             end
#         end
#     end

#     return
# end


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


function get_path(prefix::Vector, suffix::Vector; dir = false, warn = true)

    for i in prefix
        for j in suffix
            fname = joinpath(i, j)
            if isfile(fname) || (dir && isdir(fname))
                return fname
            end
        end
    end
    
    if warn
        @warn "No option for $suffix found"
    end

    return
end

get_path(prefix::String, suffix::String; kwargs...) = get_path([prefix], [suffix]; kwargs...)
get_path(prefix::String, suffix::Vector; kwargs...) = get_path([prefix], suffix; kwargs...)
get_path(prefix::Vector, suffix::String; kwargs...) = get_path(prefix, [suffix]; kwargs...)

# import Mustache

# function install(source, destination; parameters = Dict(), force = false, executable = false)

#     if isfile(destination) 
#         if force
#             rm(destination)
#         else
#             error("$destination already exists. Use force = true to overwrite")
#         end
#     else
#         mkpath(dirname(destination))
#     end

#     if !isempty(parameters)
#         template = Mustache.load(source)

#         open(destination, "w") do file
#             Mustache.render(file, template, parameters)
#         end
#     else
#         cp(source, destination)
#     end

#     if executable
#         chmod(destination, 0o755)
#     end

#     return
# end

# """
# Move directories from source to destination. 
# Only recurse into directories that already exist in destination.
# """
# function merge_directories(source::String, destination::String; overwrite::Bool=false)
    
#     if !isdir(source)
#         error("Source directory does not exist: $source")
#     end
    
#     # Create destination if needed
#     !isdir(destination) && mkpath(destination)
    
#     # Get top-level items
#     for item in readdir(source)
#         src_path = joinpath(source, item)
#         dest_path = joinpath(destination, item)
        
#         if isdir(src_path)
#             # Try to move entire directory
#             if !isdir(dest_path)
#                 # Destination doesn't exist, move whole directory
#                 mv(src_path, dest_path)
#                 println("Moved directory: $item")
#             else
#                 # Destination exists, recurse into it
#                 println("Merging into existing directory: $item")
#                 merge_directories(src_path, dest_path; overwrite=overwrite)
#             end
#         else
#             # Move file
#             mv(src_path, dest_path; force=overwrite)
#             println("Moved file: $item")
#         end
#     end
# end


