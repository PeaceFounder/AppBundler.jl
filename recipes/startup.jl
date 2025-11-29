# # This is a default startup file that is used for staging Julia which Platform-independent startup configuration
# # It is superseeded with platform specific startup.jl file in order to support varios customizations, like precompilation and etc

# libdir = dirname(dirname(@__DIR__))

# # Add paths to LOAD_PATH for proper package precompilation:
# # - Without the app directory in LOAD_PATH, extensions fail to precompile
# # - If removed after precompilation, it invalidates the package image 
# empty!(LOAD_PATH)
# push!(LOAD_PATH, "@", "@stdlib")
# isempty("{{MODULE_NAME}}") ? push!(LOAD_PATH, joinpath(Sys.STDLIB, "MainEnv")) : push!(LOAD_PATH, joinpath(Sys.STDLIB, "{{MODULE_NAME}}"))

# user_depot = get(ENV, "USER_DATA", mktempdir())

# empty!(DEPOT_PATH)
# push!(DEPOT_PATH, user_depot, joinpath(libdir, "share/julia"))

# include("common.jl")

#import AppEnv
#AppEnv.init(runtime_mode = "MIN", module_name = "{{MODULE_NAME}}")

import AppEnv
AppEnv.init(;
    runtime_mode = "{{RUNTIME_MODE}}", 
    module_name = "{{MODULE_NAME}}",
    (!isempty("{{APP_NAME}}") ? (app_name = "{{APP_NAME}}",) : ())...,
    (!isempty("{{BUNDLE_IDENTIFIER}}") ? (bundle_identifier = "{{BUNDLE_IDENTIFIER}}",) : ())...
)
