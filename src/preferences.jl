struct ColorString end

const HEX_COLOR_RE = r"^#(?:[0-9A-Fa-f]{3,4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})\z"
is_hex_color(s::AbstractString) = occursin(HEX_COLOR_RE, s)

ArgTools.coerce(::ColorString, value) = is_hex_color(value) ? value : throw(ArgTools.CoercionError("expects color hex, got '$v'")) # 
PrefTools.isallowed(::ColorString, value) = is_hex_color(value)

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
    #"msix.store_icon_plate" => String,
    "msix.store_icon_plate" => ColorString(),
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

function set_default!(f::Function, dict::AbstractDict, key::AbstractString)
    parts = split(key, '.')
    for part in parts[1:end-1]
        dict = get!(Dict{String, Any}, dict, part)
        dict isa AbstractDict || error("cannot set default for $key: `$part` is not a table")
    end
    return get!(f, dict, parts[end])
end

set_default!(dict::AbstractDict, key::AbstractString, value) = set_default!(() -> value, dict, key)

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

    module_name = get!(preferences, "module_name") do
        runs_module ? get_module_name(project_toml) : ""
    end

    # Could introduce getnested! method 
    if runs_module


        set_default!(preferences, "snap.command", ["bin/julia", "-m", module_name])
        set_default!(preferences, "appimage.command", ["bin/julia", "--eval", "using $module_name", "--"])
        set_default!(preferences, "dmg.command", ["Libraries/bin/julia", "--eval", "using $module_name", "--"])
        set_default!(preferences, "msix.command", ["bin\\julia.exe", "--eval", "using $module_name"])

    else
        app_exe = preferences["bundler"] == "juliaimg" ? "julia" : preferences["app_exe"]

        set_default!(preferences, "snap.command", ["bin/$app_exe"])
        set_default!(preferences, "appimage.command", ["bin/$app_exe"])
        set_default!(preferences, "dmg.command", ["Libraries/bin/$app_exe"])
        set_default!(preferences, "msix.command", ["bin\\$app_exe.exe"])
    end

    return
end

function load_preferences(project; defines = Pair{String, Any}[], schema = LOCAL_PREFERENCES_SCHEMA)

    #preferences = deepcopy(Resources.get_project_preferences(project))
    preferences = deepcopy(PrefTools.get_project_preferences(project))
    PrefTools.validate(preferences["AppBundler"], schema)

    overrides = ArgTools.coerce(defines, schema)

    PrefTools.apply_overrides!(preferences["AppBundler"], overrides)
    apply_defaults!(preferences["AppBundler"], project)

    return preferences
end

preferences_status(project; schema = LOCAL_PREFERENCES_SCHEMA, defines = Pair{String,Any}[]) = PrefTools.preferences_status(project, schema; infer! = x -> apply_defaults!(x, project), defines)
