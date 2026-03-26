module JuliaC

using ..AppBundler: BuildSpec
import ..AppBundler: stage
using ..Resources
using ..Resources: get_module_name

import AppEnv

function juliac()

    juliac_exe = Sys.iswindows() ? "juliac.bat" : "juliac"

    # It may be worth to iterate over PATH to look for executable
    # However it is unclear what precedance it should take

    for i in Base.DEPOT_PATH
        path = joinpath(i, "bin", juliac_exe)
        if isfile(path)
            return path
        end
    end

    path = joinpath(homedir(), ".julia", "bin", juliac_exe)
    if isfile(path)
        return path
    end

    error("Commmadn juliac not found")
end

"""
    JuliaCBundle(project; kwargs...)
 
Build specification for compiling a Julia application into a native executable via `juliac`.
 
Unlike `JuliaImgBundle`, which stages a full Julia runtime alongside precompiled package
images, `JuliaCBundle` ahead-of-time compiles the application into a standalone native
executable. The `juliac` tool must be installed and is looked up in `bin/juliac` under each
entry of `DEPOT_PATH`, with `~/.julia/bin` as a final fallback.
 
# Arguments
- `project::String`: Path to the application directory containing `Project.toml`
 
# Keyword Arguments
- `juliac_cmd::Cmd = Cmd([juliac()])`: Command used to invoke `juliac`. Defaults to the
  first `juliac` executable found on `DEPOT_PATH`
- `executable_name::String`: Name of the produced executable. Defaults to the lowercase
  module name derived from `Project.toml`
- `trim::Bool = false`: When `true`, passes `--trim=safe` to `juliac`, removing unreachable
  code from the output binary
- `args::Cmd = \`\``: Additional arguments forwarded verbatim to `juliac`
- `asset_spec::Dict{Symbol,Vector{String}} = Dict()`: Selective asset inclusion rules.
  When empty, no assets are copied into the bundle
- `asset_rpath::String = "assets"`: Destination subdirectory for assets inside `destination`
 
# Examples
```julia
# Minimal: compile with defaults
pkg = JuliaCBundle("path/to/app")
 
# Enable dead-code trimming and a custom executable name
pkg = JuliaCBundle("path/to/app"; executable_name = "myapp", trim = true)
```
"""
@kwdef struct JuliaCBundle <: BuildSpec
    project::String
    juliac_cmd::Cmd = Cmd([juliac()])
#    executable_name::String = lowercase(get_module_name(project))
    trim::Bool = false
    args::Cmd = ``
    asset_rpath::String = "assets"
    asset_spec::Dict{Symbol, Vector{String}} = Dict{Symbol, Vector{String}}()
end

JuliaCBundle(project; kwargs...) = JuliaCBundle(; project, kwargs...)

"""
    stage(spec::JuliaCBundle, destination::String;
          runtime_mode = "MIN",
          app_name = get_module_name(spec.project),
          bundle_identifier = "")
 
Compile a Julia application into a native executable and assemble it in `destination`.
 
The staging process:
1. Saves an AppEnv config to `destination/config` with runtime identity and load-path settings
2. Installs assets from `spec.asset_spec` into `destination/<asset_rpath>`
3. Writes a pkgorigin index to `destination/index` for asset resolution at runtime
4. Invokes `juliac` to AOT-compile the application and bundle the result into `destination`
 
Unlike `JuliaImgBundle`, no Julia runtime tarball is downloaded — `juliac` produces a
self-contained native binary. The host toolchain must be compatible with the target.
 
# Arguments
- `spec::JuliaCBundle`: Compilation and asset configuration
- `destination::String`: Directory in which the compiled application is assembled
 
# Keyword Arguments
- `runtime_mode`: AppEnv runtime mode string passed to `AppEnv.save_config`
- `app_name`: Application name embedded in the AppEnv config; defaults to the module name
- `bundle_identifier`: Bundle identifier embedded in the AppEnv config (e.g. reverse-DNS on macOS)
 
# Examples
```julia
pkg = JuliaCBundle("src/MyApp")
 
# Stage into a directory
stage(pkg, "build/myapp";
      app_name = "MyApp", bundle_identifier = "com.example.myapp")
 
# Stage with a custom runtime mode
stage(pkg, "build/staging"; runtime_mode = "SANDBOX")
```
"""
function stage(spec::JuliaCBundle, destination::String; runtime_mode = "MIN", app_name = get_module_name(spec.project), bundle_identifier = "")

    (; project, juliac_cmd) = spec

    trim_arg = spec.trim ? `--trim=safe` : ``
    stdlib_project_name = get_module_name(project)

    config_path = joinpath(destination, "config")
    AppEnv.save_config(config_path; runtime_mode, stdlib_project_name, app_name, bundle_identifier)

    Resources.install_assets(project, joinpath(destination, spec.asset_rpath), spec.asset_spec)
    Resources.install_pkgorigin_index(project, joinpath(destination, "index"), spec.asset_rpath)

    run(`$juliac_cmd --output-exe $(app_name) $project --bundle $destination $trim_arg $(spec.args)`)
    
    return
end

export stage, JuliaCBundle

end
