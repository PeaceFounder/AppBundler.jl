using Random: RandomDevice
using Base64

# function generate_windows_signing_certificate(destination; person_name = "AppBundler", country = "XX", validity_days = 365, force=false, publisher="O=AppBundler, C=$country, CN=$person_name")

#     password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))

#     if isfile(destination) && !force
#         error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
#     end

#     mkpath(dirname(destination))
    
#     MSIXPack.generate_self_signed_certificate(destination; password, publisher, validity_days)

#     println("""
#     The certificate is encrypted with a strong encryption algorithm and stored at meta/windows/certificate.pfx; To use certificate set certificate password "$password"
#     """)
    
#     return password
# end


function is_windows_compatible(filename::String; path_length_threshold)
    # Check for invalid characters

    if occursin(r"[<>:\"\\\|?*\x00-\x1F]", filename) || occursin(r"[\x7F-\x9F]", filename)
        @warn "$(filename) contains invalid characters for Windows."
        return false
    end

    # Check for reserved names
    reserved_names = ["CON", "PRN", "AUX", "NUL"]
    reserved_names_with_numbers = [string(name, i) for name in ["COM", "LPT"] for i in 1:9]
    append!(reserved_names, reserved_names_with_numbers)

    basename_no_ext = splitext(basename(filename))[1]
    if uppercase(basename_no_ext) in reserved_names
        @warn "$filename is a reserved name in Windows.\n"
        return false
    end

    # Check filename length (Windows max path is 260 characters)
    if length(filename) > path_length_threshold
        @warn "$filename exceeds Windows max path length.\n"
        return false
    end

    return true
end

function ensure_windows_compatability(src_dir::String; path_length_threshold::Int = 260, skip_long_paths::Bool = false, skip_symlinks = false, skip_unicode_paths=false)

    error_paths = []
    
    max_length = 0

    for (root, dirs, files) in walkdir(src_dir; follow_symlinks=false)
        for file in files
            filepath = joinpath(root, file)
            rel_path = relpath(filepath, src_dir)

            if skip_symlinks && islink(filepath)
                rm(filepath)
                println("Removed symlink: $filepath")
                continue
            end
            
            if skip_long_paths && length(rel_path) > path_length_threshold
                rm(filepath)
                println("Removed long path: $filepath")
                continue
            end

            if skip_unicode_paths && !isascii(file)
                rm(filepath)
                println("Removed unicode path: $filepath")
                continue
            end

            if Sys.isunix() && !is_windows_compatible(rel_path; path_length_threshold)
                push!(error_paths, rel_path)
                error("Aborting due to Windows-incompatible filename.")
            end

            if length(rel_path) > max_length
                max_length = length(rel_path)
            end
        end

        for dir in dirs
            dirpath = joinpath(root, dir)
            if skip_symlinks && islink(dirpath)
                rm(dirpath)
                println("Removed symlink: $dirpath")
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



"""
    xml_escape_args(args) -> String

Turn an argument list (or a `Cmd`, whose first element is dropped as the executable)
into a string suitable for an AppxManifest `Parameters="..."` attribute: arguments are
quoted following Windows argv rules and then escaped for an XML attribute.
"""
function xml_escape_args(args::AbstractVector{<:AbstractString})
    isempty(args) && return ""
    cmdline = Base.escape_microsoft_c_args(args...)   # Windows argv quoting
    return xml_escape_attr(cmdline)                   # XML attribute escaping
end

xml_escape_args(cmd::Cmd) = xml_escape_args(cmd[2:end])

function xml_escape_attr(s::AbstractString)
    io = IOBuffer()
    for c in s
        if     c == '&'  print(io, "&amp;")
        elseif c == '<'  print(io, "&lt;")
        elseif c == '>'  print(io, "&gt;")
        elseif c == '"'  print(io, "&quot;")
        elseif c == '\'' print(io, "&apos;")
        elseif c == '\t' print(io, "&#9;")    # otherwise normalized to a space
        elseif c == '\n' print(io, "&#10;")
        elseif c == '\r' print(io, "&#13;")
        elseif c < ' '
            throw(ArgumentError("control character $(repr(c)) cannot appear in XML 1.0"))
        else
            print(io, c)
        end
    end
    return String(take!(io))
end

