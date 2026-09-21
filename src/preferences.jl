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
    parameters["APP_NAME"] = lowercase(join(split(preferences["app_name"], " "), "-")) 

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


function merge_dynamic_defaults!(preferences, project_dir)

    project_toml = joinpath(project_dir, "Project.toml")

    if preferences["bundler"] == "juliaimg" && !preferences["juliaimg_mainless"]
        if !haskey(preferences, "module_name")
            module_name = get_module_name(project_toml)
            preferences["module_name"] = module_name
        end
    end

    if !haskey(preferences, "app_name")
        if isfile(project_toml)
            if preferences["juliaimg_mainless"]
                project_name = get_project_name(project_toml)
                preferences["app_name"] = project_name
            else
                # A bit convoluted logic here
                preferences["app_name"] = preferences["module_name"]
            end
        else
            error("app_name not specified in LocalPrefrences.toml and can't be infered")
        end
    end
    
    if !haskey(preferences, "app_display_name")
        preferences["app_display_name"] = preferences["app_name"]
    end

    if !haskey(preferences, "version")
        preferences["version"] = get_project_version(project_toml)
    end

    if !haskey(preferences, "build_number")
        preferences["build_number"] = commit_count(project_dir)
    end

    if !haskey(preferences, "bundle_identifier")
        preferences["bundle_identifier"] = "org.appbundler." * lowercase(preferences["app_name"])
    end
    
    return
end


function get_preferences_schema()

    preferences = TOML.parse(String(read(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml"))))["AppBundler"]
    #merge_dynamic_defaults!(preferences, project) # this is not a good option

    preferences["module_name"] = "module_name"
    preferences["app_name"] = "app_name"
    preferences["app_display_name"] = ""
    preferences["bundle_identifier"] = ""
    preferences["version"] = ""
    preferences["build_number"] = 12

    return preferences
end

function get_project_preferences(project)

    # hopefully the right call here
    preferences = Resources.get_project_preferences(project)["AppBundler"]
    merge_dynamic_defaults!(preferences, project)

    return preferences
end
