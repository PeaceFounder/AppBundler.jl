# This is a default startup file that is used for staging Julia which Platform-independent startup configuration
# It is superseeded with platform specific startup.jl file in order to support varios customizations, like precompilation and etc

libdir = dirname(dirname(@__DIR__))

# Set up LOAD_PATH
empty!(LOAD_PATH)

#push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), "@stdlib")

#push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), joinpath(libdir, "share/julia/packages/{{MODULE_NAME}}"), "@stdlib")
#push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), "@stdlib", joinpath(libdir, "share/julia/packages/GLApp"))

#push!(LOAD_PATH, "@", "@stdlib", "@stdlib/GLApp")

#push!(LOAD_PATH, "@", "@stdlib/GLApp", "@stdlib")

#push!(LOAD_PATH, "@", "@stdlib", joinpath(libdir, "share/julia/stdlib/v1.12/GLApp"))
#push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/stdlib/v1.12/"), joinpath(libdir, "share/julia/stdlib/v1.12/GLApp"))
push!(LOAD_PATH, "@", "@stdlib")
isempty("{{MODULE_NAME}}") || push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}")) # 

user_depot = get(ENV, "USER_DATA", mktempdir())

empty!(DEPOT_PATH)
push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))
