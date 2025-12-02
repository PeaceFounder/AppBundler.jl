# Startup Configuration File 
#
# This file runs after platform-specific arguments are set, allowing you to apply
# common startup options across all environments. Use this file to:
#   - Load development tools (e.g., Revise.jl for hot-reloading, Infiltrator.jl for debugging)
#   - Configure environment-specific settings
#   - Display diagnostic information about the Julia environment
#
# The diagnostic output below shows the active project, load paths, and depot paths
# to help verify your environment configuration.

# We want to support AppEnv.inis() within the main function; Eventaully we shall transition using Preferences
ENV["RUNTIME_MODE"] = "{{RUNTIME_MODE}}"
ENV["MODULE_NAME"] = "{{MODULE_NAME}}"
ENV["APP_NAME"] = "{{APP_NAME}}"
ENV["BUNDLE_IDENTIFIER"] = "{{BUNDLE_IDENTIFIER}}"

if isdir(joinpath(last(DEPOT_PATH), "compiled/v$(VERSION.major).$(VERSION.minor)", "AppEnv")) || any(i -> i.name == "AppEnv", keys(Base.loaded_modules))
    import AppEnv
else
    include(joinpath(Sys.STDLIB, "AppEnv/src/AppEnv.jl"))
end
AppEnv.init()

# AppEnv.init(;
#     runtime_mode = "{{RUNTIME_MODE}}", 
#     module_name = "{{MODULE_NAME}}",
#     (!isempty("{{APP_NAME}}") ? (app_name = "{{APP_NAME}}",) : ())...,
#     (!isempty("{{BUNDLE_IDENTIFIER}}") ? (bundle_identifier = "{{BUNDLE_IDENTIFIER}}",) : ())...
# )

Base.ACTIVE_PROJECT[] = AppEnv.USER_DATA

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    println("No arguments provided. To display help, use:")

    if Sys.iswindows()
        println("  {{APP_NAME}}.exe --eval \"using {{MODULE_NAME}}\" --help")
    else
        julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
        println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
    end
end
