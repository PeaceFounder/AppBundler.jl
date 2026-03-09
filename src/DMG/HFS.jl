"""
HFS+ Filesystem Explorer and Extractor using libdmg-hfsplus

This module was completely vibe coded iteratively with Claude.
Starting from a verbose procedural approach, it was refined through
multiple iterations to arrive at this clean, functional design.

A Julia module for exploring and extracting files from HFS+ disk images,
which exists because the extractall command in hfsplus does not work.

# Example Usage

```julia
using HFS

# Open an HFS+ disk image
img = HFS.HFSImage("mydisk.dmg")

# List directory contents and query file metadata
files = readdir(img, "/")
stat = HFS.query(img, "/MyApp.app")

# Print filesystem tree
HFS.explore_hfs_image("mydisk.dmg")
HFS.explore(img, max_depth=5)

# Extract files
HFS.extract_file(img, "/path/to/file.txt", "local_file.txt")
dirs, files = HFS.extract_tree(img, "/Applications", "extracted_apps/")
HFS.extract_hfs_filesystem("mydisk.dmg", "output_directory/")
```
"""
module HFS

using libdmg_hfsplus_jll: hfsplus


# Simple HFS+ image type
struct HFSImage
    path::String
    
    function HFSImage(path::String)
        if !isfile(path)
            throw(ArgumentError("HFS+ image file not found: $path"))
        end
        
        # Test if we can read the image (suppress output)
        try
            run(pipeline(`$(hfsplus()) $path ls /`, stdout=devnull, stderr=devnull))
        catch e
            throw(ArgumentError("Cannot read HFS+ image: $e"))
        end
        
        new(path)
    end
end

# Metadata structure for query results
struct HFSStat
    name::String
    path::String
    permissions::String
    size::Int64
    is_directory::Bool
    is_symlink::Bool
    is_file::Bool
end

# Base methods
Base.show(io::IO, img::HFSImage) = print(io, "HFSImage(\"$(img.path)\")")

"""
    parse_ls_line(line::String) -> Vector{String}

Parse an HFS+ ls output line correctly, handling padded dates.
Format: permissions user group size date time filename
Example: "040755 501  20            1 10/ 1/2025 20:31 gtkapp.app"

Returns a vector where:
- parts[1] = permissions
- parts[2] = user
- parts[3] = group  
- parts[4] = size
- parts[5] = date (e.g., "10/1/2025")
- parts[6] = time
- parts[7:end] = filename
"""
function parse_ls_line(line::AbstractString)
    tokens = split(line)
    
    if length(tokens) < 7
        return tokens
    end
    
    # First 4 parts: permissions, user, group, size
    parts = tokens[1:4]
    
    # Find date components (tokens with '/') and concatenate them
    idx = 5
    date_str = ""
    while idx <= length(tokens) && occursin('/', tokens[idx])
        date_str *= tokens[idx]
        idx += 1
    end
    push!(parts, date_str)
    
    # Next is time (contains ':')
    if idx <= length(tokens) && occursin(':', tokens[idx])
        push!(parts, tokens[idx])
        idx += 1
    end
    
    # Remaining tokens are the filename
    append!(parts, tokens[idx:end])

    return parts
end

# Core function to list directory contents
function _list_directory(img::HFSImage, dir_path::String)::Vector{String}
    entries = String[]
    
    try
        # Redirect stderr to suppress verbose hfsplus output
        listing_output = read(pipeline(`$(hfsplus()) $(img.path) ls $dir_path`, stderr=devnull), String)

        for line in split(listing_output, '\n')
            line = strip(line)
            
            # Skip empty lines and summary
            if isempty(line) || occursin("Total filesystem size:", line)
                continue
            end
            
            # Parse ls output: permissions user group size date time filename
            parts = parse_ls_line(line)
            if length(parts) >= 7
                filename = join(parts[7:end], " ")
                
                # Skip . and .. entries
                if filename in [".", ".."]
                    continue
                end
                
                # Skip problematic system directories
                if _is_system_directory(filename)
                    continue
                end
                
                # Construct full path
                full_path = dir_path == "/" ? "/$filename" : "$dir_path/$filename"

                if isempty(filename)
                    error("Something went wrong. Filename is empty")
                end

                push!(entries, full_path)
            end
        end
    catch e
        @warn "Error listing directory $dir_path: $e"
    end
    
    return entries
end

# Utility functions
function _is_system_directory(filename::String)
    return filename in ["HFS+ Private Data", ".HFS+ Private Directory Data"] || 
           occursin('\0', filename) || 
           occursin("Private Data", filename)
end

function _parse_permissions(permissions::AbstractString)
    permissions_str = String(permissions)  # Convert to String if it's a SubString
    is_directory = startswith(permissions_str, "d") || startswith(permissions_str, "04")
    is_symlink = startswith(permissions_str, "l") || startswith(permissions_str, "12")
    is_file = !is_directory && !is_symlink
    return is_directory, is_symlink, is_file
end

# Main query function - like stat() but for HFS+ paths
"""
    query(img::HFSImage, path::String) -> HFSStat

Get metadata for a specific path in the HFS+ image, similar to stat().
Returns an HFSStat object with file information including size, permissions,
and type flags (is_directory, is_symlink, is_file).

# Examples
```julia
img = HFSImage("disk.dmg")
stat = query(img, "/Applications/MyApp.app")
println("Size: \$(stat.size) bytes")
println("Is directory: \$(stat.is_directory)")
```
"""
function query(img::HFSImage, path::String)
    # Get the parent directory and filename
    if path == "/"
        # Special case for root
        return HFSStat("/", "/", "drwxr-xr-x", 0, true, false, false)
    end
    
    parent_dir = dirname(path)
    filename = basename(path)
    
    try
        # Suppress verbose hfsplus output
        listing_output = read(pipeline(`$(hfsplus()) $(img.path) ls $parent_dir`, stderr=devnull), String)
        
        for line in split(listing_output, '\n')
            line = strip(line)
            
            if isempty(line) || occursin("Total filesystem size:", line)
                continue
            end
            
            parts = parse_ls_line(line)
            if length(parts) >= 7
                permissions = parts[1]
                size_str = parts[4]
                file_name = join(parts[7:end], " ")
                
                if file_name == filename
                    size = tryparse(Int64, size_str)
                    size = size === nothing ? 0 : size
                    
                    is_directory, is_symlink, is_file = _parse_permissions(permissions)
                    
                    return HFSStat(filename, path, permissions, size, 
                                 is_directory, is_symlink, is_file)
                end
            end
        end
    catch e
        throw(ArgumentError("Cannot query path $path: $e"))
    end
    
    throw(ArgumentError("Path not found: $path"))
end

# High-level interface functions
"""
    readdir(img::HFSImage, path::String = "/") -> Vector{String}

List contents of a directory (non-recursive), returns just the filenames.
Similar to Base.readdir() but for HFS+ images.

# Examples
```julia
img = HFSImage("disk.dmg")
files = readdir(img, "/Applications")
```
"""
function Base.readdir(img::HFSImage, path::String = "/")
    full_paths = _list_directory(img, path)
    return [basename(p) for p in full_paths]
end

# File extraction
"""
    extract_file(img::HFSImage, src_path::String, dest_path::String) -> Bool

Extract a single file from the HFS+ image.
Returns true if successful, false otherwise.

# Examples
```julia
img = HFSImage("disk.dmg")
success = extract_file(img, "/path/to/file.txt", "local_file.txt")
```
"""
function extract_file(img::HFSImage, src_path::String, dest_path::String)
    try
        # Suppress verbose hfsplus output during extraction
        run(pipeline(`$(hfsplus()) $(img.path) extract $src_path $dest_path`, stdout=devnull, stderr=devnull))
        return true
    catch e
        return false
    end
end

"""
    extract_tree(img::HFSImage, src_path::String, dest_path::String) -> Tuple{Int, Int}

Extract an entire directory tree from the HFS+ image.
Returns (directory_count, file_count).

# Examples
```julia
img = HFSImage("disk.dmg")
dirs, files = extract_tree(img, "/Applications", "extracted_apps/")
```
"""
function extract_tree(img::HFSImage, src_path::String, dest_path::String)
    # Create root destination directory
    mkpath(dest_path)
    
    dir_count, file_count = _extract_recursive(img, src_path, dest_path)
    
    return dir_count + 1, file_count  # +1 for root dest_path
end

function _extract_recursive(img::HFSImage, src_path::String, dest_path::String)
    directory_count = 0
    file_count = 0
    
    #try
    entries = readdir(img, src_path)
    
    for entry in entries
        entry_src_path = src_path == "/" ? "/$entry" : "$src_path/$entry"
        entry_dest_path = joinpath(dest_path, entry)
        
        #try
        stat_info = query(img, entry_src_path)
        
        if stat_info.is_directory
            # Create directory
            mkpath(entry_dest_path)
            directory_count += 1
            
            # Recurse into directory
            sub_dirs, sub_files = _extract_recursive(img, entry_src_path, entry_dest_path)
            directory_count += sub_dirs
            file_count += sub_files
            
        elseif stat_info.is_file
            # Extract file
            if extract_file(img, entry_src_path, entry_dest_path)
                file_count += 1
            end
            
        else  # symlink
            @warn "Skipping symlink: $entry_src_path"
        end
    end
    
    return directory_count, file_count
end

# Pretty printing for stat
function Base.show(io::IO, stat::HFSStat)
    type_char = stat.is_directory ? "📁" : (stat.is_symlink ? "🔗" : "📄")
    size_info = stat.is_file ? " ($(stat.size) bytes)" : ""
    print(io, "$type_char $(stat.name)$size_info")
end

# User-facing functions that match the original interface
"""
    explore_hfs_image(hfs_image_path::String)

Explore and print the entire HFS+ structure. Original interface function.
Provides a tree view of the filesystem with files and directories.

# Examples
```julia
HFS.explore_hfs_image("disk.dmg")
```
"""
function explore_hfs_image(hfs_image_path::String)
    img = HFSImage(hfs_image_path)
    explore(img)
end

"""
    extract_hfs_filesystem(hfs_image_path::String, destination_dir::String)

Extract entire HFS+ filesystem silently. Only warns about skipped symlinks.

# Examples
```julia
HFS.extract_hfs_filesystem("disk.dmg", "extracted_contents/")
```
"""
function extract_hfs_filesystem(hfs_image_path::String, destination_dir::String)
    img = HFSImage(hfs_image_path)
    directory_count, file_count = extract_tree(img, "/", destination_dir)
    return directory_count, file_count
end

"""
    explore(img::HFSImage; max_depth::Int = 3)

Print a tree view of the HFS+ image contents.
Shows a hierarchical view of directories and files with size information.

# Examples
```julia
img = HFSImage("disk.dmg")
explore(img, max_depth=5)  # Show deeper tree
```
"""
function explore(img::HFSImage; max_depth::Int = 3)
    println("=== HFS+ Image Structure ===")
    println("Image: $(img.path)")
    println()
    
    _print_tree(img, "/", "", 0, max_depth)
end

function _print_tree(img::HFSImage, path::String, prefix::String, depth::Int, max_depth::Int)
    if depth > max_depth
        return
    end
    
    try
        entries = readdir(img, path)
        
        for (i, entry) in enumerate(entries)
            is_last = i == length(entries)
            entry_path = path == "/" ? "/$entry" : "$path/$entry"
            
            # Print current entry
            connector = is_last ? "└── " : "├── "
            
            try
                stat_info = query(img, entry_path)
                
                if stat_info.is_directory
                    println(prefix * connector * "📁 " * entry * "/")
                    # Recurse into directory
                    next_prefix = prefix * (is_last ? "    " : "│   ")
                    _print_tree(img, entry_path, next_prefix, depth + 1, max_depth)
                elseif stat_info.is_symlink
                    println(prefix * connector * "🔗 " * entry)
                else
                    println(prefix * connector * "📄 " * entry * " (" * string(stat_info.size) * " bytes)")
                end
            catch e
                println(prefix * connector * "❌ " * entry * " (error: " * string(e) * ")")
            end
        end
    catch e
        println(prefix * "└── ❌ Error reading " * path * ": " * string(e))
    end
end

end # module HFS
