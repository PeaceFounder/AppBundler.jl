module JuliaC

using ..AppBundler: BuildSpec
using ..Resources
using ..Resources: get_module_name

import AppEnv


@kwdef struct JuliaCBundle <: BuildSpec
    project::String
    juliac_cmd::Cmd = Cmd([joinpath(homedir(), ".julia/bin", "juliac")])
    executable_name::String = lowercase(get_module_name(project))
    trim::Bool = false
    args::Cmd = ``
    stdlib::String = "assets"
    runtime_mode::String = "MIN"
    app_name = executable_name
    bundle_identifier = ""
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

function reset_appenv()

    compilation_cache = joinpath(first(DEPOT_PATH), "compiled")

    for dir in readdir(compilation_cache)
        cache_path = joinpath(compilation_cache, dir, "AppEnv")
        if isdir(cache_path)
            rm(cache_path; recursive=true, force=true)
        end
    end
    
end

function stage(spec::JuliaCBundle, destination::String)

    (; project, juliac_cmd) = spec

    trim_arg = spec.trim ? `--trim=safe` : ``
    module_name = get_module_name(project)

    # This is a blunt way to invalidate a compilation cache, but currently seems the best way to do so
    reset_appenv()
    
    withenv(
        "DEFAULT_RUNTIME_MODE" => spec.runtime_mode,
        "MODULE_NAME" => module_name, 
        "STDLIB" => spec.stdlib, 
        "APP_NAME" => spec.app_name, 
        "BUNDLE_IDENTIFIER" => spec.bundle_identifier
    ) do
        run(`$juliac_cmd --output-exe $(spec.executable_name) $project --bundle $destination $trim_arg $(spec.args)`)
    end

    install_assets(project, joinpath(destination, spec.stdlib))
    
    return
end

end
