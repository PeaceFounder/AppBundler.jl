module JuliaC

using ..AppBundler: BuildSpec
import ..AppBundler: stage
using ..Resources
using ..Resources: get_module_name

import AppEnv


const JULIAC_PKGID = Base.PkgId(Base.UUID("acedd4c2-ced6-4a15-accc-2607eb759ba2"), "JuliaC")
const JULIAC_EXE = Sys.iswindows() ? "juliac.bat" : "juliac"

"""
    juliac_shim() -> Union{String, Nothing}

Locate the `juliac` app shim installed via `pkg> app add JuliaC`. Depots are searched
in `DEPOT_PATH` order, then `~/.julia` (in case `JULIA_DEPOT_PATH` excludes it),
and finally `PATH` as a last resort.
"""
function juliac_shim()
    for depot in unique([Base.DEPOT_PATH; joinpath(homedir(), ".julia")])
        path = joinpath(depot, "bin", JULIAC_EXE)
        isfile(path) && return path
    end
    return Sys.which(JULIAC_EXE)
end


"""
    get_juliac() -> Cmd

Resolve the command used to invoke juliac:

1. the `JULIAC` environment variable, if set;
2. the `juliac` app shim, when no project is active or AppBundler's own project is active;
3. JuliaC from the active meta project, pinned by its manifest.
"""
function get_juliac()
    project = Base.active_project()

    if haskey(ENV, "JULIAC")
        return Cmd([ENV["JULIAC"]])

    elseif isnothing(Base.ACTIVE_PROJECT[]) || samefile(dirname(project), pkgdir(@__MODULE__))
        shim = juliac_shim()
        isnothing(shim) && error("""
            Could not resolve the juliac shim. Install it with `pkg> app add JuliaC`, or
            launch AppBundler with `julia --project=<meta> -m AppBundler`, where the meta
            project has JuliaC added (recommended, since its manifest pins both JuliaC
            and AppBundler).
            """)
        return Cmd([shim])

    elseif Base.project_deps_get(project, "JuliaC") == JULIAC_PKGID
        julia = Base.julia_cmd()[1]
        cmd = `$julia --startup-file=no --project=$project -m JuliaC`
        return addenv(cmd, "JULIA_LOAD_PATH" => "@")

    else
        error("JuliaC is not available in the active project environment $project.")
    end
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
    juliac_cmd::Cmd = get_juliac()
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
