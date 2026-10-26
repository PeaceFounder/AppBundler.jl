
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
    "msix.store_icon_plate" => String,
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


function extract_template_parameters!(parameters::Dict{String, Any}, preferences)

    # This one looks like a bug nest; need to refactor and test
    parameters["APP_NAME"] = preferences["app_name"]
    parameters["APP_EXE"] = preferences["app_exe"]

    if haskey(preferences, "module_name")
        parameters["MODULE_NAME"] = preferences["module_name"]
    end

    parameters["APP_DISPLAY_NAME"] = preferences["app_display_name"]
    parameters["APP_VERSION"] = preferences["version"]
    parameters["BUILD_NUMBER"] = preferences["build_number"]
    parameters["APP_SUMMARY"] = preferences["app_summary"]
    parameters["APP_DESCRIPTION"] = preferences["app_description"]
    parameters["BUNDLE_IDENTIFIER"] = preferences["bundle_identifier"]
    parameters["PUBLISHER_DISPLAY_NAME"] = preferences["publisher_name"]


    # can't put here because it's possible to create inconsistent bundle struct here
    # parameters["WINDOWED"] = preferences["windowed"]
    # parameters["PUBLISHER"] = preferences["msix_publisher"] |> normalize_publisher

    return parameters
end

function get_bundle_parameters!(parameters::Dict{String, Any}, preferences)
    return extract_template_parameters!(parameters, preferences)
end

function get_bundle_parameters(preferences)
    return extract_template_parameters!(Dict{String, Any}(), preferences)
end



section!(prefs::Dict, name) = get!(Dict{String,Any}, prefs, name)

#function merge_dynamic_defaults!(preferences::Dict, project_dir)
function apply_defaults!(preferences::Dict, project_dir)

    project_toml = joinpath(project_dir, "Project.toml")

    app_name = get!(preferences, "app_name") do
        isfile(project_toml) || error("app_name not specified in LocalPreferences.toml and can't be inferred")
        get_project_name(project_toml)
    end

    get!(preferences, "app_exe") do
        lowercase(join(split(app_name, " "), "-"))
    end

    get!(preferences, "app_display_name", app_name)

    get!(preferences, "version") do
        get_project_version(project_toml)
    end

    get!(preferences, "build_number") do
        commit_count(project_dir)
    end

    get!(preferences, "bundle_identifier") do
        "org.appbundler." * lowercase(app_name)
    end

    runs_module = preferences["bundler"] == "juliaimg" && !get(preferences["juliaimg"], "mainless", false)

    # Could introduce getnested! method 
    if runs_module
        module_name = get!(preferences, "module_name") do
            get_module_name(project_toml)
        end

        get!(get!(Dict{String,Any}, preferences, "snap"), "command", ["bin/julia", "-m", module_name])
        get!(get!(Dict{String,Any}, preferences, "appimage"), "command", ["bin/julia", "--eval", "using $module_name", "--"])
        get!(get!(Dict{String,Any}, preferences, "dmg"), "command", ["Libraries/bin/julia", "--eval", "using $module_name", "--"])
        get!(get!(Dict{String,Any}, preferences, "msix"), "command", ["bin\\julia.exe", "--eval", "using $module_name"])
    else
        app_exe = preferences["bundler"] == "juliaimg" ? "julia" : preferences["app_exe"]

        get!(get!(Dict{String,Any}, preferences, "snap"), "command", ["bin/$app_exe"])
        get!(get!(Dict{String,Any}, preferences, "appimage"), "command", ["bin/$app_exe"])
        get!(get!(Dict{String,Any}, preferences, "dmg"), "command", ["Libraries/bin/$app_exe"])
        get!(get!(Dict{String,Any}, preferences, "msix"), "command", ["bin\\$app_exe.exe"])
    end

    return
end


"""
    nest_keys(flat) -> Dict{String, Any}

Inverse of [`flatten_schema`](@ref): turn `"juliaimg.sysimg" => ["GtkApp"]` into
`"juliaimg" => Dict("sysimg" => ["GtkApp"])`.
"""
function nest_keys(flat)
    nested = Dict{String, Any}()
    for (key, value) in flat
        parts = split(key, '.')
        node = nested
        for part in parts[1:end-1]
            node = get!(Dict{String, Any}, node, String(part))
        end
        node[String(parts[end])] = value
    end
    return nested
end

"""
    flatten_schema(schema) -> Dict{String, Any}

Map every value in a nested schema to its dotted path, `"juliaimg.sysimg" => []`.
Tables themselves get no entry.
"""
function flatten_schema(schema::AbstractDict, prefix::AbstractString = "")
    flat = Dict{String, Any}()
    for (key, value) in schema
        path = isempty(prefix) ? key : "$prefix.$key"
        if value isa AbstractDict
            merge!(flat, flatten_schema(value, path))
        else
            flat[path] = value
        end
    end
    return flat
end


function apply_overrides!(preferences, overrides)

    preference_overrides = nest_keys(overrides)

    custom_merge(a::Dict, b::Dict) = merge(a, b)
    custom_merge(a::T, b::T) where T = b
    custom_merge(a, b) = error("Incompatable types")

    mergewith!(custom_merge, preferences, preference_overrides)
    
    return preferences
end

# ── Validation of a full preferences dictionary ───────────────────────────────

# A value fits a type spec when it is an instance of it
isallowed(spec::Type, value) = value isa spec

# Allowed values: the value must be one of the listed options
isallowed(options::Tuple, value) = value in options

# TOML may parse a list as `Vector{Any}` (always so for `[]`), so check the elements instead
isallowed(::Type{Vector{String}}, value) =
    value isa AbstractVector && all(x -> x isa AbstractString, value)

describe(spec::Type) = "a value of type $spec"
describe(::Type{Vector{String}}) = "a list of strings"
describe(options::Tuple) = "one of " * join(repr.(options), ", ")


"""
    validate(preferences, schema = LOCAL_PREFERENCES_SCHEMA)

Check every (flattened) key of `preferences` against the schema. Reports all unknown keys and
invalid values together; returns `preferences` unchanged when everything is valid.
"""
function validate(preferences::AbstractDict, schema::AbstractDict = LOCAL_PREFERENCES_SCHEMA)
    problems = String[]
    for (key, value) in flatten_schema(preferences)
        key = string(key)
        if !haskey(schema, key)
            push!(problems, "unknown preference `$key`")
        elseif !isallowed(schema[key], value)
            push!(problems, "`$key` must be $(describe(schema[key])), got $(repr(value))")
        end
    end
    isempty(problems) || error("Invalid preferences:\n  " * join(sort!(problems), "\n  "))
    return preferences
end


function load_preferences(project; defines = Pair{String, Any}[], schema = LOCAL_PREFERENCES_SCHEMA)

    preferences = deepcopy(Resources.get_project_preferences(project))
    validate(preferences["AppBundler"], schema)

    overrides = ArgTools.coerce(defines, schema)

    apply_overrides!(preferences["AppBundler"], overrides)
    apply_defaults!(preferences["AppBundler"], project)

    return preferences
end

