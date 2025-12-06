module JuliaC

using ..AppBundler: BuildSpec
import ..AppBundler: stage
using ..Resources
using ..Resources: get_module_name

import AppEnv

@kwdef struct JuliaCBundle <: BuildSpec
    project::String
    juliac_cmd::Cmd = Cmd([joinpath(homedir(), ".julia/bin", Sys.iswindows() ? "juliac.bat" : "juliac")])
    executable_name::String = lowercase(get_module_name(project))
    trim::Bool = false
    args::Cmd = ``
    stdlib::String = "assets"
end

JuliaCBundle(project; kwargs...) = JuliaCBundle(; project, kwargs...)

function remove_jl_sources!(dir)

    for (root, dirs, files) in walkdir(dir; topdown=false)
        # Remove all .jl files
        for file in files
            if endswith(file, ".jl") || file == "Project.toml" || file == "Manifest.toml"
                filepath = joinpath(root, file)
                rm(filepath)
            end
        end
        
        # Remove directory if empty (skip the top-level dir)
        if root != dir && isempty(readdir(root))
            rm(root)
        end
    end

    return
end

# This is a bit of a hack but shall be enough to prove the concept
function install_assets(project, destination)

    mkpath(destination)
    Resources.retrieve_packages(project, destination)
    pkgorigins = AppEnv.collect_pkgorigins(; stdlib_dir = destination)
    AppEnv.save_pkgorigins(joinpath(destination, "index"), pkgorigins; stdlib_dir = destination)
    remove_jl_sources!(destination)

    return
end

function compile_appenv(juliac_cmd, project_path)

    # Work around two platform-specific limitations in juliac shim scripts:
    # 1. Scripts executed before the `--` separator run in the JuliaC environment,
    #    not the target project, so we can't directly compile AppEnv there
    # 2. The `--eval` flag combined with `--` separator has quoting bugs on all
    #    platforms (shell word-splitting on Unix, delayed expansion issues on Windows),
    #    so we use a temporary file instead of inline code

    APPENV_PKGID = Base.PkgId(Base.UUID("9f11263e-cf0d-4932-bae6-807953dbea74"), "AppEnv")
    
    # Get Julia binary directory by running a script through juliac shim
    # (Script runs before `--` separator to execute in JuliaC environment)
    bindir_query_script = tempname()
    write(bindir_query_script, 
          """
          print(Sys.BINDIR)
          exit()
          """)
    
    julia_bindir = read(`$juliac_cmd $bindir_query_script --`, String)
    julia = joinpath(julia_bindir, "julia")
    
    # Pre-compile AppEnv in the target project environment
    try
        run(`$julia --startup-file=no --project=$project_path --eval "Base.compilecache($(repr(APPENV_PKGID))); exit()"`)
    catch
        @warn "Failed to pre-compile AppEnv. It may not be listed in project dependencies. Continuing anyway..."
    end
    
    return nothing
end

function stage(spec::JuliaCBundle, destination::String; runtime_mode = "MIN", app_name = get_module_name(spec.project), bundle_identifier = "")

    (; project, juliac_cmd) = spec

    trim_arg = spec.trim ? `--trim=safe` : ``
    module_name = get_module_name(project)

    try
        withenv(
            "DEFAULT_RUNTIME_MODE" => runtime_mode,
            "MODULE_NAME" => module_name, 
            "STDLIB" => spec.stdlib, 
            "APP_NAME" => app_name, 
            "BUNDLE_IDENTIFIER" => bundle_identifier
        ) do
            compile_appenv(juliac_cmd, project)
            run(`$juliac_cmd --output-exe $(spec.executable_name) $project --bundle $destination $trim_arg $(spec.args)`)
        end
    finally
        # Resetting AppEnv for interactive use
        @async compile_appenv(juliac_cmd, project)
    end

    install_assets(project, joinpath(destination, spec.stdlib))
    
    return
end

export stage

end
