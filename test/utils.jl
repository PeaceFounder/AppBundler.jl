function hash_stage(f)
    stage = mktempdir()
    f(stage)
    return hash_directory(stage)
end

# Read file and compute SHA-256 hash
function hash_file(filename)
    hash_bytes = sha256(read(filename))
    hash_string = bytes2hex(hash_bytes)
    return hash_string
end    

function hash_directory(dir_path)
    if !isdir(dir_path)
        error("Directory not found: $dir_path")
    end
    
    # Get all files recursively and sort for consistency
    all_files = String[]
    for (root, dirs, files) in walkdir(dir_path)
        for file in files
            push!(all_files, joinpath(root, file))
        end
    end
    sort!(all_files)  # Ensure consistent ordering

    # Create hash context properly
    ctx = SHA.SHA256_CTX()  # Create context this way
    
    # Hash each file's content
    for filepath in all_files
        file_data = read(filepath)
        #println("$(hash(file_data)): $filepath")
        SHA.update!(ctx, file_data)
    end
    
    return bytes2hex(SHA.digest!(ctx))
end

function mount_dmg(target_path)

    mount_result = read(`hdiutil attach $target_path -nobrowse -readonly -noverify`, String)

    mount_lines = split(mount_result, '\n')
    for line in mount_lines
        (devpoint, spec, mount_point) = split(line, '\t')
        if !isempty(mount_point)
            return mount_point
        end
    end

    error("No mount point for $target_path")
end

unmount_dmg(mount_point) = run(`hdiutil detach $mount_point`)
