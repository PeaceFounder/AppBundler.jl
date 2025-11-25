# Startup Configuration File (common startup.jl)
#
# This file runs after platform-specific arguments are set, allowing you to apply
# common startup options across all environments. Use this file to:
#   - Load development tools (e.g., Revise.jl for hot-reloading, Infiltrator.jl for debugging)
#   - Configure environment-specific settings
#   - Display diagnostic information about the Julia environment
#
# The diagnostic output below shows the active project, load paths, and depot paths
# to help verify your environment configuration.

# @info "Active project is $(Base.ACTIVE_PROJECT[])"
# @info "LOAD_PATH = $LOAD_PATH"
# @info "DEPOT_PATH = $DEPOT_PATH"
# @info "USER_DATA = $(ENV["USER_DATA"])"

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    println("No arguments provided. To display help, use:")

    if Sys.iswindows()
        println("  {{APP_NAME}}.exe --eval \"using {{MODULE_NAME}}\" --help")
    else
        julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
        println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
    end
end

# ToDo: update this script
function fill_stdlib_pkgorigins!()
    stdlib_dir = Sys.STDLIB
    
    uuid_regex = r"^uuid\s*=\s*\"([a-f0-9\-]+)\""mi
    version_regex = r"^version\s*=\s*\"([^\"]+)\""mi
    
    for name in readdir(stdlib_dir)
        pkg_path = joinpath(stdlib_dir, name)
        
        # Skip if not a directory
        isdir(pkg_path) || continue
        
        # Look for Project.toml
        project_file = joinpath(pkg_path, "Project.toml")
        isfile(project_file) || continue
        
        # Read file content
        content = read(project_file, String)
        
        # Extract uuid
        uuid_match = match(uuid_regex, content)
        uuid_match === nothing && continue
        uuid = Base.UUID(uuid_match[1])
        
        # Extract version (optional)
        version_match = match(version_regex, content)
        version = version_match === nothing ? nothing : VersionNumber(version_match[1])
        
        # Find the module file path (typically src/<name>.jl)
        module_file = joinpath(pkg_path, "src", "$name.jl")
        if !isfile(module_file)
            # Skip if module file doesn't exist
            continue
        end
        
        # Create PkgId and PkgOrigin
        pkg_id = Base.PkgId(uuid, name)
        pkg_origin = Base.PkgOrigin(module_file, nothing, version)
        
        # Add to pkgorigins
        Base.pkgorigins[pkg_id] = pkg_origin
    end
    
    return Base.pkgorigins
end

fill_stdlib_pkgorigins!()
