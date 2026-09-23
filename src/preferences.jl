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
    #parameters["APP_NAME"] = lowercase(join(split(preferences["app_name"], " "), "-")) 
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

function merge_dynamic_defaults!(preferences::Dict, project_dir)

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

function get_preferences_schema()

    preferences = TOML.parse(String(read(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml"))))["AppBundler"]
    #merge_dynamic_defaults!(preferences, project) # this is not a good option

    preferences["app_name"] = "myapp"
    preferences["bundler"] = "juliac"
    preferences["build_number"] = 1
    preferences["version"] = "0.0.1"
    
    merge_dynamic_defaults!(preferences, "")

    return preferences
end

function get_extended_preferences(project; preference_overrides = Dict())

    # hopefully the right call here
    preferences = deepcopy(Resources.get_project_preferences(project))
    #merge!(preferences["AppBundler"], preference_overrides)

    custom_merge(a::Dict, b::Dict) = merge(a, b)
    custom_merge(a::T, b::T) where T = b
    custom_merge(a, b) = error("Incompatable types")
    mergewith!(custom_merge, preferences["AppBundler"], preference_overrides)

    merge_dynamic_defaults!(preferences["AppBundler"], project)

    return preferences
end

get_project_preferences(project) = get_extended_preferences(project)["AppBundler"]
