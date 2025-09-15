# This is a default startup file that is used for staging Julia which Platform-independent startup configuration
# It is superseeded with platform specific startup.jl file in order to support varios customizations, like precompilation and etc

libdir = dirname(dirname(@__DIR__))

# Set up LOAD_PATH
empty!(LOAD_PATH)
push!(LOAD_PATH, "@", joinpath(libdir, "share/julia/packages"), "@stdlib")

user_depot = get(ENV, "USER_DATA", mktempdir())

empty!(DEPOT_PATH)
push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))

