# Startup Configuration File (common startup.jl)
#
# This file runs after platform-specific arguments are set, allowing you to apply
# common startup options across all environments. Use this file to:
#   - Load development tools (e.g., Revise.jl for hot-reloading, Infiltrator.jl for debugging)
#   - Configure environment-specific settings
#   - Display diagnostic information about the Julia environment
#
# The diagnostic output below shows the active project, load paths, and depot paths
# to help verify your environment configuration.

# @info "Active project is $(Base.ACTIVE_PROJECT[])"
# @info "LOAD_PATH = $LOAD_PATH"
# @info "DEPOT_PATH = $DEPOT_PATH"
# @info "USER_DATA = $(ENV["USER_DATA"])"

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    println("No arguments provided. To display help, use:")

    if Sys.iswindows()
        println("  {{APP_NAME}}.exe --eval \"using {{MODULE_NAME}}\" --help")
    else
        julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
        println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
    end
end

