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
    asset_rpath::String = "assets"
    asset_spec::Dict{Symbol, Vector{String}} = Dict{Symbol, Vector{String}}()
end

JuliaCBundle(project; kwargs...) = JuliaCBundle(; project, kwargs...)

function stage(spec::JuliaCBundle, destination::String; runtime_mode = "MIN", app_name = get_module_name(spec.project), bundle_identifier = "")

    (; project, juliac_cmd) = spec

    trim_arg = spec.trim ? `--trim=safe` : ``
    stdlib_project_name = get_module_name(project)

    config_path = joinpath(destination, "config")
    AppEnv.save_config(config_path; runtime_mode, stdlib_project_name, app_name, bundle_identifier)

    Resources.install_assets(project, joinpath(destination, spec.asset_rpath), spec.asset_spec)
    Resources.install_pkgorigin_index(project, joinpath(destination, "index"), spec.asset_rpath)

    run(`$juliac_cmd --output-exe $(spec.executable_name) $project --bundle $destination $trim_arg $(spec.args)`)
    
    return
end

export stage

end
