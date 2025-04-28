import Mustache
import TOML

struct Rule
    origin::String
    dest::String
    template::Bool
    executable::Bool
    override::Bool
end

isvalid(rule::Rule, default::String, override::String) =  ispath(joinpath(default, rule.origin)) || ispath(joinpath(override, rule.origin))

struct Bundle
    default::String
    override::String
    rules::Vector{Rule}
end

Bundle(default::String, override::String) = Bundle(default, override, Rule[])

add_rule!(bundle::Bundle, rule::Rule) = push!(bundle.rules, rule)
add_rule!(bundle::Bundle, origin, dest; template=false, executable=false, override=false) = add_rule!(bundle, Rule(origin, dest, template, executable, override))

function issubpath(path::String, subpath::String)

    path_dirs = split(path, "/")
    first(path_dirs) == "" && popfirst!(path_dirs)
    last(path_dirs) == "" && pop!(path_dirs)

    subpath_dirs = split(subpath, "/")
    first(subpath_dirs) == "" && popfirst!(subpath_dirs)
    last(subpath_dirs) == "" && pop!(subpath_dirs)

    if length(subpath_dirs) < length(path_dirs)
        return false
    else
        for i in 1:length(path_dirs)
            if path_dirs[i] != subpath_dirs[i]
                return false
            end        
        end

        return true
    end
end

# Only writes a file if the target does not exist
function merge(source::AbstractString, target::AbstractString)
    # Check if source and target are directories
    if !isdir(source)
        if isfile(source) && !isfile(target)
            cp(source, target)
        end
        return
    end
    # Iterate over each item in the source directory
    for item in readdir(source)
        src_path = joinpath(source, item)
        dest_path = joinpath(target, item)
        
        if isdir(src_path)
            # If the item is a directory and doesn't exist in the target, create it
            if !isdir(dest_path)
                mkpath(dest_path)
            end
            # Recursively merge subdirectories
            merge(src_path, dest_path)
        elseif isfile(src_path)
            # If the item is a file and doesn't exist in the target, copy it
            if !isfile(dest_path)
                #println("$src_path => $dest_path")
                isdir(dirname(dest_path)) || mkpath(dirname(dest_path))
                cp(src_path, dest_path)
            end
        end
    end
end

function build(bundle::Bundle, destination::String, parameters::Dict)

    for (i, rule) in enumerate(bundle.rules)

        dest_path = joinpath(destination, rule.dest)

        # A rule which provides a whoole direcotry is more specific
        for j in 1:(i - 1)
            if issubpath(bundle.rules[j].dest, rule.dest) && isvalid(bundle.rules[j], bundle.default, bundle.override)
                @info "Rule $(rule.dest) is skipped as overriden by $(bundle.rules[j].dest)."
                @goto skip
            end                
        end
            
        if ispath(joinpath(bundle.override, rule.origin))
            source = joinpath(bundle.override, rule.origin)
        elseif ispath(joinpath(bundle.default, rule.origin))
            source = joinpath(bundle.default, rule.origin)
        else
            @info "Rule with origin $(rule.origin) is skipped as not found in default or override path."
            continue
        end

        mkpath(dirname(dest_path))
        
        if rule.template == true
            if isfile(source)

                template = Mustache.load(source)
                
                open(dest_path, "w") do file
                    Mustache.render(file, template, parameters)
                end
                # cp(source, dest_path) # a template can be supported for individual files
            else
                # This could be done with executing specific rule first
                # and latter adding a directory in a merged way. 
                @warn "Applying a template to a direcotry is not supported."
            end
        else
            #cp(source, dest_path)
            merge(joinpath(bundle.override, rule.origin), dest_path)
            merge(joinpath(bundle.default, rule.origin), dest_path)

        end

        if isfile(dest_path) && rule.executable == true
            chmod(dest_path, 0o755)
        end

        @label skip
    end
    
    return
end

function get_bundle_parameters(project_toml)

    toml_dict = TOML.parsefile(project_toml)

    parameters = Dict{String, Any}()

    parameters["MODULE_NAME"] = get(toml_dict, "name", "MainEntry")

    app_name = haskey(toml_dict, "APP_NAME") ? toml_dict["APP_NAME"] : haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))
    parameters["APP_NAME"] = lowercase(join(split(app_name, " "), "-"))
    #parameters["APP_DIR_NAME"] = haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))

    parameters["APP_VERSION"] = haskey(toml_dict, "version") ? toml_dict["version"] : "0.0.1"

    # Setting defaults
    parameters["APP_DISPLAY_NAME"] = app_name #parameters["APP_NAME"]
    parameters["APP_SUMMARY"] = "This is a default app summary"
    parameters["APP_DESCRIPTION"] = "A longer description of the app"
    parameters["WITH_SPLASH_SCREEN"] = "false"
    parameters["BUNDLE_IDENTIFIER"] = "org.appbundler." * lowercase(parameters["APP_NAME"])
    parameters["PUBLISHER"] = "CN=AppBundler"
    parameters["PUBLISHER_DISPLAY_NAME"] = "AppBundler"
    parameters["BUILD_NUMBER"] = 0
    
    if haskey(toml_dict, "bundle")
        for (key, value) in toml_dict["bundle"]
            parameters[key] = string(value) # Mustache does not print false.
        end
    end
    
    return parameters
end
