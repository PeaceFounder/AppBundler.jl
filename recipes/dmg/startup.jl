# This file should contain site-specific commands to be executed on Julia startup;
# Users may store their own personal commands in `~/.julia/config/startup.jl`.

if haskey(ENV, "USER_DATA")
    @info "Using USER_DATA environment variable to run in custom location"
    user_depot = joinpath(ENV["USER_DATA"], "depot")
elseif !haskey(ENV, "APP_SANDBOX_CONTAINER_ID")
    @info "Running outside SandBox environment"
    user_depot = joinpath(homedir(), ".cache", "{{APP_NAME}}")
    ENV["USER_DATA"] = joinpath(homedir(), ".config", "{{APP_NAME}}")
else
    @info "Running in a SandBox environment"
    user_depot = joinpath(homedir(), "Library", "Caches", "depot")
    ENV["USER_DATA"] = joinpath(homedir(), "Library", "Application Support", "Local")
end

libdir = dirname(dirname(@__DIR__))

empty!(LOAD_PATH)
push!(LOAD_PATH, "@", "@stdlib")
isempty("{{MODULE_NAME}}") || push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}")) # 

#push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), "@stdlib", joinpath(libdir, "share/julia/packages/{{MODULE_NAME}}"))

# Modify DEPOT_PATH (equivalent to JULIA_DEPOT_PATH)
empty!(DEPOT_PATH)
push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))

Base.ACTIVE_PROJECT[] = ENV["USER_DATA"]

@info "Active project is $(Base.ACTIVE_PROJECT[])"
@info "LOAD_PATH = $LOAD_PATH"
@info "DEPOT_PATH = $DEPOT_PATH"
@info "USER_DATA = $(ENV["USER_DATA"])"

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
    println("No arguments provided. To display help, use:")
    println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
end
