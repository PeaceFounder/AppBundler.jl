# Need to set up environment variables just like done on macos and windows

libdir = dirname(dirname(@__DIR__))

empty!(LOAD_PATH)
push!(LOAD_PATH, "@", "@stdlib")
isempty("{{MODULE_NAME}}") || push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}"))

empty!(DEPOT_PATH)
push!(DEPOT_PATH, joinpath(libdir, "share/julia"))

if haskey(ENV, "SNAP")
    @info "Application running as SNAP"

    ENV["USER_DATA"] = ENV["SNAP_USER_DATA"]

    # correct
    pushfirst!(DEPOT_PATH, ENV["SNAP_DATA"])
    pushfirst!(DEPOT_PATH, ENV["SNAP_USER_COMMON"])
    
else
    @info "Application running in bare host environment."

    if !haskey(ENV, "USER_DATA")
        ENV["USER_DATA"] = joinpath(tempdir(), "{{APP_NAME}}")
    end

    pushfirst!(DEPOT_PATH, joinpath(ENV["USER_DATA"], "cache"))

end

Base.ACTIVE_PROJECT[] = ENV["USER_DATA"]

@info "Active project is $(Base.ACTIVE_PROJECT[])"
@info "LOAD_PATH = $LOAD_PATH"
@info "DEPOT_PATH = $DEPOT_PATH"
@info "USER_DATA = $(ENV["USER_DATA"])"

function __precompile__()
    popfirst!(DEPOT_PATH)
    @eval import {{MODULE_NAME}}
end

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
    println("No arguments provided. To display help, use:")
    println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
end
