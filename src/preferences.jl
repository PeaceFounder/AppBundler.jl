"""A colour written as `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`, e.g. the MSIX store icon plate."""
struct HexColor end

const HEX_COLOR_RE = r"^#(?:[0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\z"
is_hex_color(s::AbstractString) = occursin(HEX_COLOR_RE, s)

function Knobs.coerce(value, ::HexColor)
    value isa AbstractString && is_hex_color(strip(value)) && return String(strip(value))
    throw(Knobs.CoercionError("expects a hex colour like #f3f3f3, got $(repr(value))"))
end

"""
Every preference AppBundler reads, as a flat dotted key mapped to its spec. Defaults
live in `LocalPreferences.toml` at the package root; values computed from the project are
the rules in [`inference_layer`](@ref).
"""
const LOCAL_PREFERENCES_SCHEMA = Dict{String, Any}(
    "app_name" => String,
    "app_display_name" => String,
    "app_exe" => String,
    "app_summary" => String,
    "app_description" => String,
    "bundle_identifier" => String,
    "module_name" => String,
    "publisher_name" => String,
    "version" => String,
    "build_number" => Int,

    "bundler" => ("juliaimg", "juliac"),
    "windowed" => Bool,
    "compress" => Bool,
    "selfsign" => Bool,
    "skipsign" => Bool,
    "overwrite_target" => Bool,
    "verbose" => Bool,

    "juliaimg.precompile" => Bool,
    "juliaimg.incremental" => Bool,
    "juliaimg.mainless" => Bool,
    "juliaimg.selective_assets" => Bool,
    "juliaimg.sysimg" => Vector{String},

    "juliac.trim" => Bool,

    "msix.command" => Vector{String},
    "msix.publisher" => String,
    "msix.store_icon_plate" => HexColor(),
    "msix.path_length_threshold" => Int,
    "msix.skip_long_paths" => Bool,
    "msix.skip_symlinks" => Bool,
    "msix.skip_unicode_paths" => Bool,
    "msix.bootstrapper" => Bool,
    "msix.bootstrapper_windowed" => Bool,

    "dmg.command" => Vector{String},
    "dmg.backend" => ("xorriso", "hfsplus"),
    "dmg.compression" => ("lzma", "bzip2", "zlib", "lzfse"),
    "dmg.hardened_runtime" => Bool,
    "dmg.sandboxed_runtime" => Bool,
    "dmg.shallow_signing" => Bool,
    "dmg.xorriso.hfsplus" => Bool,
    "dmg.hfsplus.free_space" => Int,

    "snap.command" => Vector{String},

    "appimage.command" => Vector{String},
    "appimage.compression" => ("zstd", "gzip", "xz"),
)


function get_module_name(project_toml)

    project_name = get_project_name(project_toml)

    if !isnothing(project_name) && isfile(joinpath(dirname(project_toml), "src", project_name * ".jl"))
        return project_name
    else
        error("Main module name can't be infered from the project. In case thats intentiional use `juliaimg_mainless = true` in LocalPrefereces.toml")
    end
end

function get_project_name(project_toml)

    toml_dict = TOML.parsefile(project_toml)
    if haskey(toml_dict, "name") 
        return toml_dict["name"]
    else
        return nothing
    end
end


function get_project_version(project_toml)
    toml_dict = TOML.parsefile(project_toml)
    return get(toml_dict, "version", "0.0.1")
end

function commit_count(repo_path = ".")
    
    local repo
    try
        repo = LibGit2.GitRepo(repo_path)
    catch
        return 0
    end

    try
        head = LibGit2.head_oid(repo)
        walker = LibGit2.GitRevWalker(repo)
        LibGit2.push!(walker, head)
        count = 0
        for _ in walker
            count += 1
        end
        return count
    finally
        close(repo)
    end
end

"""
    inference_layer(project_dir) -> Vector{Pair{String, Any}}

Preferences computed from the project when no layer sets them: names and version
from `Project.toml`, the build number from the git history, and the launch commands
from the bundler and the main module. Several rules for one key are alternatives,
tried in order; see [`Knobs.Rule`](@ref).
"""
function inference_layer(project_dir)

    project_toml = joinpath(project_dir, "Project.toml")

    return Pair{String, Any}[
        "app_name" => Knobs.Rule() do
            isfile(project_toml) || error("app_name not specified in LocalPreferences.toml and can't be inferred")
            get_project_name(project_toml)
        end,
        "app_exe"           => Knobs.Rule("app_name") do app_name; lowercase(join(split(app_name, " "), "-")) end,
        "app_display_name"  => Knobs.Rule(identity, "app_name"),
        "version"           => Knobs.Rule() do; get_project_version(project_toml) end,
        "build_number"      => Knobs.Rule() do; commit_count(project_dir) end,
        "bundle_identifier" => Knobs.Rule("app_name") do app_name; "org.appbundler." * lowercase(app_name) end,

        "module_name" => Knobs.Rule("bundler", "juliaimg.mainless") do bundler, mainless
            bundler == "juliaimg" && !mainless ? get_module_name(project_toml) : ""
        end,

        # Launch commands, two alternatives each. A juliaimg app with a main module runs it
        # through the bundled Julia; otherwise the first rule declines and the second starts
        # the executable: `julia` itself for a mainless juliaimg app, the app for juliac.
        "snap.command" => Knobs.Rule("bundler", "juliaimg.mainless", "module_name") do bundler, mainless, module_name
            bundler == "juliaimg" && !mainless ? ["bin/julia", "-m", module_name] : nothing
        end,
        "snap.command" => Knobs.Rule("bundler", "app_exe") do bundler, app_exe
            bundler == "juliaimg" ? ["bin/julia"] : ["bin/$app_exe"]
        end,

        "appimage.command" => Knobs.Rule("bundler", "juliaimg.mainless", "module_name") do bundler, mainless, module_name
            bundler == "juliaimg" && !mainless ? ["bin/julia", "--eval", "using $module_name", "--"] : nothing
        end,
        "appimage.command" => Knobs.Rule("bundler", "app_exe") do bundler, app_exe
            bundler == "juliaimg" ? ["bin/julia"] : ["bin/$app_exe"]
        end,

        "dmg.command" => Knobs.Rule("bundler", "juliaimg.mainless", "module_name") do bundler, mainless, module_name
            bundler == "juliaimg" && !mainless ? ["Libraries/bin/julia", "--eval", "using $module_name", "--"] : nothing
        end,
        "dmg.command" => Knobs.Rule("bundler", "app_exe") do bundler, app_exe
            bundler == "juliaimg" ? ["Libraries/bin/julia"] : ["Libraries/bin/$app_exe"]
        end,

        "msix.command" => Knobs.Rule("bundler", "juliaimg.mainless", "module_name") do bundler, mainless, module_name
            bundler == "juliaimg" && !mainless ? ["bin\\julia.exe", "--eval", "using $module_name"] : nothing
        end,
        "msix.command" => Knobs.Rule("bundler", "app_exe") do bundler, app_exe
            bundler == "juliaimg" ? ["bin\\julia.exe"] : ["bin\\$app_exe.exe"]
        end,
    ]
end

"""AppBundler's default preferences, shipped with the package."""
const DEFAULT_PREFERENCES = joinpath(dirname(@__DIR__), "LocalPreferences.toml")

"""
    load_layer(path; section = "AppBundler") -> Vector{Pair{String, Any}}

The `[section]` table of the TOML file at `path` as a layer of flat dotted pairs
for Knobs. A missing file or section gives an empty layer.
"""
function load_layer(path; section = "AppBundler")
    isfile(path) || return Pair{String, Any}[]
    table = get(TOML.parsefile(path), section, Dict{String, Any}())
    table isa AbstractDict || error("$path: [$section] is not a table")
    return Knobs.flatten(table)
end

"""
    preference_layers(project; defines = []) -> Vector

The layers AppBundler resolves, lowest precedence first: values inferred from the
project, the shipped defaults, the project's `LocalPreferences.toml` and the
command-line `defines`.
"""
function preference_layers(project; defines = Pair{String, Any}[])
    return [
        "inferred"              => inference_layer(project),
        "defaults"              => load_layer(DEFAULT_PREFERENCES),
        "LocalPreferences.toml" => load_layer(joinpath(project, "LocalPreferences.toml")),
        "command line"          => defines,
    ]
end

"""
    project_preferences(project; defines = []) -> Dict{String, Any}

The project's resolved `[AppBundler]` preferences as a nested dictionary:
`preferences["dmg"]["backend"]`. Throws listing every invalid or missing preference.
"""
function project_preferences(project::AbstractString; defines = Pair{String, Any}[], schema = LOCAL_PREFERENCES_SCHEMA)
    resolved = Knobs.resolve(schema, preference_layers(project; defines))
    return Knobs.nest(resolved)
end
