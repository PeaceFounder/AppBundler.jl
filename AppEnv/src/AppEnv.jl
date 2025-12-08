module AppEnv

import Base: PkgId, PkgOrigin, UUID

const RUNTIME_MODE_OPTIONS = ["MIN", "INTERACTIVE", "COMPILATION", "SANDBOX"]

# Compilation can be done in one mode
#const DEFAULT_RUNTIME_MODE = get(ENV, "DEFAULT_RUNTIME_MODE", get(ENV, "RUNTIME_MODE", "INTERACTIVE"))

#get(ENV, "JULIA_RUNTIME_MODE", "INTERACTIVE") # We set it at compilation

#const DEFAULT_MODULE_NAME = get(ENV, "MODULE_NAME", "MainEnv")
#const DEFAULT_APP_NAME = get(ENV, "APP_NAME", "")
#const DEFAULT_BUNDLE_IDENTIFIER = get(ENV, "BUNDLE_IDENTIFIER", "")

#const DEFAULT_STDLIB = get(ENV, "STDLIB", relpath(Sys.STDLIB, dirname(Sys.BINDIR)))

# println("Compilation is about to happen with the following parameters:")
# println("\tDEFAULT_RUNTIME_MODE=" * DEFAULT_RUNTIME_MODE)
# println("\tDEFAULT_MODULE_NAME=" * DEFAULT_MODULE_NAME)
# println("\tDEFAULT_APP_NAME=" * DEFAULT_APP_NAME)
# println("\tDEFAULT_BUNDLE_IDENTIFIER=" * DEFAULT_BUNDLE_IDENTIFIER)

global USER_DATA::String # This is set by the startup macro itself


# Theese constants must be present at compilation time as otherwise it does not make sense

function save_pkgorigins(index_path, pkgorigins::Dict{PkgId, PkgOrigin}; root_dir = nothing)

    file = open(index_path, "w")

    try
        for (pkgid, pkgorigin) in pkgorigins

            (; name, uuid) = pkgid
            (; path, version) = pkgorigin
            
            rpath = isnothing(root_dir) ? path : relpath(path, root_dir)

            println(file, "$uuid\t$name\t$version\t$rpath")
            
        end
    finally
        close(file)
    end
end

# Helper function to manually parse version string to avoid VersionNumber(::String) type instability
# This avoids the problematic split_idents function in Base.version
function parse_version(version_str::AbstractString)
    # Handle basic version format: major.minor.patch[-prerelease][+build]
    # Split by '-' to separate version from prerelease
    parts = split(version_str, '-', limit=2)
    version_part = parts[1]
    
    # Split by '+' to separate from build metadata
    version_part = split(version_part, '+')[1]
    
    # Split by '.' to get major.minor.patch
    components = split(version_part, '.')
    
    # Parse major, minor, patch
    major = length(components) >= 1 ? parse(Int, components[1]) : 0
    minor = length(components) >= 2 ? parse(Int, components[2]) : 0
    patch = length(components) >= 3 ? parse(Int, components[3]) : 0
    
    # For now, ignore prerelease and build info to keep it simple
    # This is sufficient for most stdlib packages
    return VersionNumber(major, minor, patch)
end

function load_pkgorigins!(pkgorigins, path; root_dir = dirname(path))
    #pkgorigins = Dict{PkgId, PkgOrigin}()
    
    file = open(path, "r")
    
    try
        for line in eachline(file)
            # Parse tab-separated values
            parts = split(line, '\t')
            length(parts) == 4 || continue  # Skip malformed lines
            
            uuid_str, name, version_str, rpath = parts
            
            # Parse UUID
            uuid = UUID(uuid_str)
            
            # Parse version (handle "nothing" case)
            if version_str == "nothing"
                version = nothing
            else
                try
                    version = parse_version(version_str)
                catch e
                    @warn "Failed to parse version '$version_str' for package $name: $e"
                    continue
                end
            end
            
            # Reconstruct absolute path
            _abspath = abspath(joinpath(root_dir, rpath))
            
            # Create PkgId and PkgOrigin
            pkg_id = PkgId(uuid, name)
            pkg_origin = PkgOrigin(_abspath, nothing, version)
            
            # Add to dictionary
            pkgorigins[pkg_id] = pkg_origin
        end
    finally
        close(file)
    end
    
    return pkgorigins
end


function collect_pkgorigins!(pkgorigins::Dict{PkgId, PkgOrigin}; root_dir = Sys.STDLIB)
    
    uuid_regex = r"^uuid\s*=\s*\"([a-f0-9\-]+)\""mi
    version_regex = r"^version\s*=\s*\"([^\"]+)\""mi
    
    if !isdir(root_dir)
        return pkgorigins
    end

    for name in readdir(root_dir)
        pkg_path = joinpath(root_dir, name)
        
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
        uuid = UUID(uuid_match[1])
        
        # Extract version (optional) and parse manually
        version_match = match(version_regex, content)
        if version_match === nothing
            version = nothing
        else
            try
                version = parse_version(version_match[1])
            catch e
                @warn "Failed to parse version '$(version_match[1])' for package $name: $e"
                version = nothing
            end
        end
        
        # Find the module file path (typically src/<n>.jl)
        module_file = joinpath(pkg_path, "src", "$name.jl")
        if !isfile(module_file)
            # Skip if module file doesn't exist
            continue
        end
        
        # Create PkgId and PkgOrigin
        pkg_id = PkgId(uuid, name)
        pkg_origin = PkgOrigin(module_file, nothing, version)
        
        # Add to pkgorigins
        pkgorigins[pkg_id] = pkg_origin
    end
    
    return pkgorigins
end

collect_pkgorigins(; root_dir = Sys.STDLIB) = collect_pkgorigins!(Dict{PkgId, PkgOrigin}(); root_dir)


function set_load_path!(LOAD_PATH; stdlib_project_name)

    empty!(LOAD_PATH)
    push!(LOAD_PATH, "@", "@stdlib")
    push!(LOAD_PATH, joinpath(Sys.STDLIB, stdlib_project_name))

end

function set_depot_path!(DEPOT_PATH; bundle_identifier = "", app_name = "", runtime_mode = "MIN")

    if runtime_mode == "SANDBOX"

        if Sys.iswindows()
            set_depot_path_msix!(DEPOT_PATH; bundle_identifier)
        elseif Sys.isapple()
            set_depot_path_macos!(DEPOT_PATH; app_name)
        elseif Sys.islinux()
            set_depot_path_snap!(DEPOT_PATH)
        else
            error("Sandbox runtime mode is only supported for windows, macos and linux")
        end

    elseif runtime_mode == "MIN"

        set_depot_path_min!(DEPOT_PATH)

    else
        error("Sandbox mode RUNTIME_MODE=$runtime_mode not supported")
    end
end

function set_depot_path_min!(DEPOT_PATH)

    global USER_DATA = get(ENV, "USER_DATA", mktempdir())
    empty!(DEPOT_PATH)
    push!(DEPOT_PATH, USER_DATA, joinpath(dirname(Sys.BINDIR), "share/julia"))

end

function set_depot_path_macos!(DEPOT_PATH::Vector{String}; app_name)

    if haskey(ENV, "USER_DATA")
        @info "Using USER_DATA environment variable to run in custom location"
        global USER_DATA = ENV["USER_DATA"]
        user_depot = joinpath(USER_DATA, "depot")
    elseif haskey(ENV, "APP_SANDBOX_CONTAINER_ID")
        @info "Running in a SandBox environment"
        user_depot = joinpath(homedir(), "Library", "Caches", "depot")
        global USER_DATA = joinpath(homedir(), "Library", "Application Support", "Local")
    else
        @info "Running outside SandBox environment"
        user_depot = joinpath(homedir(), ".cache", app_name)
        global USER_DATA = joinpath(homedir(), ".config", app_name)
    end

    empty!(DEPOT_PATH)
    push!(DEPOT_PATH, user_depot, joinpath(dirname(Sys.BINDIR), "share/julia"))

    return
end

function set_depot_path_snap!(DEPOT_PATH)

    empty!(DEPOT_PATH)

    if haskey(ENV, "SNAP")
        @info "Application running as SNAP"

        global USER_DATA = ENV["SNAP_USER_DATA"]

        push!(DEPOT_PATH, ENV["SNAP_USER_COMMON"])
        push!(DEPOT_PATH, ENV["SNAP_DATA"])

    else
        @info "Application running in bare host environment."

        if haskey(ENV, "USER_DATA")
            global USER_DATA = ENV["USER_DATA"]
        else
            global USER_DATA = mktempdir() 
        end
        
        push!(DEPOT_PATH, joinpath(USER_DATA, "cache"))

    end

    push!(DEPOT_PATH, joinpath(dirname(Sys.BINDIR), "share/julia"))

    return
end

function get_basename(bundle_identifier)
    
    BASE_DIR = dirname(dirname(Sys.BINDIR))

    if basename(dirname(BASE_DIR)) == "WindowsApps"
        parts = split(basename(BASE_DIR), "_")
        return first(parts) * "_" * last(parts)
    else
        for dirname in readdir(joinpath(ENV["LOCALAPPDATA"], "Packages"))
            parts = split(basename(dirname), "_")
            if first(parts) == bundle_identifier
                return first(parts) * "_" * last(parts)
            end
        end
    end

    return
end

function set_depot_path_msix!(DEPOT_PATH; bundle_identifier)

    if haskey(ENV, "USER_DATA")
        @info "Using USER_DATA environment variable to run in custom location"
        global USER_DATA = ENV["USER_DATA"]
    else 
        _basename = get_basename(bundle_identifier)
        if !isnothing(_basename)
            @info "Using USER_DATA asigned by sandbox environment"    
            base_dir = joinpath(ENV["LOCALAPPDATA"], "Packages", _basename)
            global USER_DATA = joinpath(base_dir, "LocalState")
        else
            @info "Could not infer USER_DATA directory, presumably running out of sanbdox. Using temporary directory..."
            path = joinpath(tempdir(), "app_user_data")
            rm(path; recursive=true, force=true)
            mkpath(path)
            global USER_DATA = path
        end
    end

    @assert isdir(USER_DATA) "User data directory USER_DATA = $USER_DATA does not exist."
    user_depot = joinpath(USER_DATA, "depot")

    # Modify DEPOT_PATH (equivalent to JULIA_DEPOT_PATH)
    empty!(DEPOT_PATH)
    push!(DEPOT_PATH, user_depot, joinpath(dirname(Sys.BINDIR), "share/julia") ) # may be better to set with respect to Sys.BINDIR

    return
end

function load_config(config_path)
    config_dict = Dict{String, String}()
    
    for line in eachline(config_path)
        # Skip empty lines
        isempty(strip(line)) && continue
        
        # Split on the first '=' character
        key, value = split(line, '=', limit=2)
        config_dict[strip(key)] = strip(value)
    end

    runtime_mode = config_dict["RUNTIME_MODE"]    
    stdlib_project_name = config_dict["STDLIB_PROJECT_NAME"]
    app_name = get(config_dict, "APP_NAME", "")
    bundle_identifier = get(config_dict, "BUNDLE_IDENTIFIER", "")

    @assert runtime_mode in RUNTIME_MODE_OPTIONS

    if runtime_mode == "SANDBOX"

        if isempty(app_name)
            error("APP_NAME not set")
        end

        if isempty(bundle_identifier)
            error("BUNDLE_IDENTIFIER not set")
        end
    end

    return (; runtime_mode, stdlib_project_name, app_name, bundle_identifier)
end


function save_config(config_path; stdlib_project_name, app_name = "", bundle_identifier = "", runtime_mode = "MIN")

    @assert runtime_mode in RUNTIME_MODE_OPTIONS

    config = """
        RUNTIME_MODE=$runtime_mode
        STDLIB_PROJECT_NAME=$stdlib_project_name
        APP_NAME=$app_name
        BUNDLE_IDENTIFIER=$bundle_identifier
    """

    rm(config_path; force=true)
    write(config_path, config)

    return
end


# function init(; 
#               runtime_mode::String = get(ENV, "RUNTIME_MODE", DEFAULT_RUNTIME_MODE),
#               module_name::String = get(ENV, "MODULE_NAME", DEFAULT_MODULE_NAME),
#               app_name::String = get(ENV, "APP_NAME", DEFAULT_APP_NAME),
#               bundle_identifier::String = get(ENV, "BUNDLE_IDENTIFIER", DEFAULT_BUNDLE_IDENTIFIER)
#               )


function init(; config_path = joinpath(dirname(Sys.BINDIR), "config"),
              index_path = joinpath(dirname(Sys.BINDIR), "index"))

    # Prevents reinitialization
    if isdefined(@__MODULE__, :USER_DATA)
        return
    end

    # If config file is not present we assume it is an interactive mode
    if !isfile(config_path)
        global USER_DATA = get(ENV, "USER_DATA", mktempdir())
        return
    end

    (; runtime_mode, stdlib_project_name, app_name, bundle_identifier) = load_config(config_path)

    set_load_path!(Base.LOAD_PATH; stdlib_project_name)
    set_depot_path!(Base.DEPOT_PATH; app_name, bundle_identifier, runtime_mode)

    if isfile(index_path)
        load_pkgorigins!(Base.pkgorigins, index_path)
    else
        @warn "Can't find pkgorigin index at $index_path"
        #collect_pkgorigins!(Base.pkgorigins)
    end

    return
end


# function reset_cache()

#     pkg = Base.PkgId(Base.UUID("9f11263e-cf0d-4932-bae6-807953dbea74"), "AppEnv")
#     cache_dir = Base.compilecache_path(pkg)

#     if !isnothing(cache_dir)
#         @info "Removing the cache"
#         rm(cache_dir; recursive=true)
#     end
    
# end


end # module AppEnv
