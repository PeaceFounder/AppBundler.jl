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

import AppEnv
AppEnv.init(;
    runtime_mode = "{{RUNTIME_MODE}}", 
    module_name = "{{MODULE_NAME}}",
    (!isempty("{{APP_NAME}}") ? (app_name = "{{APP_NAME}}",) : ())...,
    (!isempty("{{BUNDLE_IDENTIFIER}}") ? (bundle_identifier = "{{BUNDLE_IDENTIFIER}}",) : ())...
)

Base.ACTIVE_PROJECT[] = AppEnv.USER_DATA

if isinteractive()
    @async begin
        @eval using Revise

        @eval import Pkg
        Base.invokelatest() do
            if isdefined(Pkg.Types, :FORMER_STDLIBS)
                empty!(Pkg.Types.FORMER_STDLIBS)
            elseif isdefined(Pkg.Types, :UPGRADABLE_STDLIBS)
                empty!(Pkg.Types.UPGRADABLE_STDLIBS)
            else
                @warn "Failed to clear upgradable stdlib list: neither FORMER_STDLIBS nor UPGRADABLE_STDLIBS found in Pkg.Types (Julia $VERSION)"
            end
        end
    end
end
