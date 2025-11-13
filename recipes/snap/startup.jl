# Need to set up environment variables just like done on macos and windows

libdir = dirname(dirname(@__DIR__))

empty!(LOAD_PATH)
push!(LOAD_PATH, "@", "@stdlib")
isempty("{{MODULE_NAME}}") ? push!(LOAD_PATH, joinpath(Sys.STDLIB, "MainEnv")) : push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}"))

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

function __precompile__()
    if !isempty("{{PRECOMPILED_MODULES}}")
        popfirst!(DEPOT_PATH)
        popfirst!(LOAD_PATH)
        @eval import {{PRECOMPILED_MODULES}}
    end
end

include("common.jl")
