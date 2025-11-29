# This file should contain site-specific commands to be executed on Julia startup;
# Users may store their own personal commands in `~/.julia/config/startup.jl`.

# if haskey(ENV, "USER_DATA")
#     @info "Using USER_DATA environment variable to run in custom location"
#     user_depot = joinpath(ENV["USER_DATA"], "depot")
# elseif !haskey(ENV, "APP_SANDBOX_CONTAINER_ID")
#     @info "Running outside SandBox environment"
#     user_depot = joinpath(homedir(), ".cache", "{{APP_NAME}}")
#     ENV["USER_DATA"] = joinpath(homedir(), ".config", "{{APP_NAME}}")
# else
#     @info "Running in a SandBox environment"
#     user_depot = joinpath(homedir(), "Library", "Caches", "depot")
#     ENV["USER_DATA"] = joinpath(homedir(), "Library", "Application Support", "Local")
# end

# libdir = dirname(dirname(@__DIR__))

# empty!(LOAD_PATH)
# push!(LOAD_PATH, "@", "@stdlib")
# isempty("{{MODULE_NAME}}") ? push!(LOAD_PATH, joinpath(Sys.STDLIB, "MainEnv")) : push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}"))

# # Modify DEPOT_PATH (equivalent to JULIA_DEPOT_PATH)
# empty!(DEPOT_PATH)
# push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))

# Base.ACTIVE_PROJECT[] = ENV["USER_DATA"]

# include("common.jl")

# We need to set environment variables for the 
#ENV["MODULE_NAME"] = "{{MODULE_NAME}}"
#ENV["APP_NAME"] = "{{APP_NAME}}"
#ENV["BUNDLE_IDENTIFIER"] = "{{BUNDLE_IDENTIFIER}}"

import AppEnv
AppEnv.init(
    runtime_mode = "SANDBOX", 
    module_name = "{{MODULE_NAME}}",
    app_name = "{{APP_NAME}}",
    bundle_identifier = "{{BUNDLE_IDENTIFIER}}"
)

