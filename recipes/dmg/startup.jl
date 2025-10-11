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

#libdir = dirname(dirname(dirname(@__DIR__)))
libdir = dirname(dirname(@__DIR__))

#Base.ACTIVE_PROJECT[] = joinpath(libdir, "{{MODULE_NAME}}")

empty!(LOAD_PATH)
push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), joinpath(libdir, "share/julia/packages/{{MODULE_NAME}}"), "@stdlib")

# Modify DEPOT_PATH (equivalent to JULIA_DEPOT_PATH)
empty!(DEPOT_PATH)
push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))

#push!(DEPOT_PATH, cache_dir, libdir, joinpath(libdir, "julia/share/julia"))

@info "Active project is $(Base.ACTIVE_PROJECT[])"
@info "LOAD_PATH = $LOAD_PATH"
@info "DEPOT_PATH = $DEPOT_PATH"
@info "USER_DATA = $(ENV["USER_DATA"])"



# function __precompile__()
#     popfirst!(DEPOT_PATH)
#     @eval using {{MODULE_NAME}}
# end

# function __main__()
#     @eval include(joinpath(Base.ACTIVE_PROJECT[], "main.jl"))
# end
