ENV["BUNDLE_IDENTIFIER"] = "{{BUNDLE_IDENTIFIER}}"
ENV["APP_NAME"] = "{{APP_NAME}}"

function get_basename()
    
    BASE_DIR = dirname(dirname(Sys.BINDIR))

    if basename(dirname(BASE_DIR)) == "WindowsApps"
        parts = split(basename(BASE_DIR), "_")
        return first(parts) * "_" * last(parts)
    else
        for dirname in readdir(joinpath(ENV["LOCALAPPDATA"], "Packages"))
            parts = split(basename(dirname), "_")
            if first(parts) == ENV["BUNDLE_IDENTIFIER"]
                return first(parts) * "_" * last(parts)
            end
        end
    end

    return
end

if haskey(ENV, "USER_DATA")
    @info "Using USER_DATA environment variable to run in custom location"
else 
    _basename = get_basename()
    if !isnothing(_basename)
        @info "Using USER_DATA asigned by sandbox environment"    
        base_dir = joinpath(ENV["LOCALAPPDATA"], "Packages", _basename)
        ENV["USER_DATA"] = joinpath(base_dir, "LocalState")
    else
        @info "Could not infer USER_DATA directory, presumably running out of sanbdox. Using temporary directory..."
        path = joinpath(tempdir(), "app_user_data")
        rm(path; recursive=true, force=true)
        mkpath(path)
        ENV["USER_DATA"] = path        
    end
end

@assert isdir(ENV["USER_DATA"]) "User data directory USER_DATA = $USER_DATA does not exist."
cache_dir = joinpath(ENV["USER_DATA"], "depot")

libdir = dirname(dirname(dirname(@__DIR__)))

Base.ACTIVE_PROJECT[] = joinpath(libdir, "{{MODULE_NAME}}")

empty!(LOAD_PATH)
push!(LOAD_PATH, joinpath(libdir, "packages"), "@stdlib", "@")

# Modify DEPOT_PATH (equivalent to JULIA_DEPOT_PATH)
empty!(DEPOT_PATH)
push!(DEPOT_PATH, cache_dir, libdir, joinpath(libdir, "julia/share/julia"))

@info "Active project is $(Base.ACTIVE_PROJECT[])"
@info "LOAD_PATH = $LOAD_PATH"
@info "DEPOT_PATH = $DEPOT_PATH"
@info "USER_DATA = $(ENV["USER_DATA"])"

function __precompile__()
    popfirst!(DEPOT_PATH)
    @eval using {{MODULE_NAME}}
end

function __main__()
    #@eval include(joinpath(libdir, "startup", "init.jl"))
    @eval include(joinpath(libdir, ENV["APP_NAME"], "main.jl"))
end
