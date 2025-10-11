# Need to set up environment variables just like done on macos and windows

#libdir = dirname(dirname(dirname(@__DIR__)))
libdir = dirname(dirname(@__DIR__))

empty!(LOAD_PATH)
push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), joinpath(libdir, "share/julia/packages/{{MODULE_NAME}}"), "@stdlib")
#push!(LOAD_PATH, joinpath(libdir, "packages"), "@stdlib", "@")

empty!(DEPOT_PATH)
push!(DEPOT_PATH, joinpath(libdir, "share/julia"))
#push!(DEPOT_PATH, libdir, joinpath(libdir, "julia/share/julia"))

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

#Base.ACTIVE_PROJECT[] = joinpath(libdir, "{{MODULE_NAME}}")

@info "Active project is $(Base.ACTIVE_PROJECT[])"
@info "LOAD_PATH = $LOAD_PATH"
@info "DEPOT_PATH = $DEPOT_PATH"
@info "USER_DATA = $(ENV["USER_DATA"])"

function __precompile__()
    popfirst!(DEPOT_PATH)
    @eval import {{MODULE_NAME}}
end

# function __main__()
#     @eval include(joinpath(Base.ACTIVE_PROJECT[], "main.jl"))
# end
