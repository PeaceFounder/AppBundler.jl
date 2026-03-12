import TOML

import LibGit2
using Preferences


function get_project_name(project_toml)

    toml_dict = TOML.parsefile(project_toml)
    if haskey(toml_dict, "name") 
        return toml_dict["name"]
    else
        return nothing
    end
end


function get_module_name(project_toml)

    toml_dict = TOML.parsefile(project_toml)
    if haskey(toml_dict, "name") && isfile(joinpath(dirname(project_toml), "src", toml_dict["name"] * ".jl"))
        return toml_dict["name"]
    else
        error("Main module name can't be infered from the project. In case thats intentiional use `juliaimg_mainless = true` in LocalPrefereces.toml")
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

get_bundle_parameters(project_toml) = get_bundle_parameters!(Dict{String, Any}(), project_toml)

function get_bundle_parameters!(parameters::Dict{String, Any}, project_toml)

    # The parameter resolution can differ depending on what is being bundled. 
    # For instance MODULE_NAME is Julia specific only.

    if @load_preference("juliaimg_mainless", false)
        project_name = get_project_name(project_toml)
        app_name = @load_preference("app_name", project_name)
    else
        module_name = get_module_name(project_toml)
        parameters["MODULE_NAME"] = module_name
        app_name = @load_preference("app_name", module_name) 
    end

    parameters["APP_NAME"] = lowercase(join(split(app_name, " "), "-"))

    @show parameters["APP_DISPLAY_NAME"] = @load_preference("app_display_name", @load_preference("app_name", app_name))

    parameters["APP_VERSION"] = get_project_version(project_toml)
    parameters["BUILD_NUMBER"] = @load_preference("build_number", commit_count(dirname(project_toml)))
    
    parameters["APP_SUMMARY"] = @load_preference("app_summary", "This is a default app summary")
    parameters["APP_DESCRIPTION"] = @load_preference("app_description", "A longer description of the app")
    
    parameters["BUNDLE_IDENTIFIER"] = @load_preference("bundle_identifier", "org.appbundler." * parameters["APP_NAME"])

    parameters["PUBLISHER_DISPLAY_NAME"] = @load_preference("publisher_name", "AppBundler")

    return parameters
end


# argument parser

function normalize_args(args)
    normalized = String[]
    for arg in args
        if startswith(arg, "--") && contains(arg, '=')
            # Split --flag=value into --flag and value
            flag, value = split(arg, '=', limit=2)
            push!(normalized, flag)
            push!(normalized, value)
        else
            push!(normalized, arg)
        end
    end
    return normalized
end

function parse_args(raw_args)

    args = normalize_args(raw_args)

    # Default values
    config = Dict(
        :build_dir => nothing,  # Use nothing to distinguish "not set" from ""
        :compress => @load_preference("compress", true),
        :windowed => @load_preference("windowed", false),
        :adhoc_signing => @load_preference("adhoc_signing", false),
        :target_arch => Sys.ARCH,
        :target_bundle => Symbol[],
        :target_name => nothing,
        :overwrite_target => @load_preference("overwrite_target", false)
    )
    
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ["--help", "-h"]
            print_help()
            exit(0)
        elseif arg == "--build-dir"
            i += 1
            if i > length(args)
                error("--build-dir requires a value")
            end
            build_dir = expanduser(args[i])
            if build_dir == "@temp"
                config[:build_dir] = mktempdir()
            else
                if !isdir(build_dir)
                    parent = dirname(build_dir)
                    if isdir(parent) || isempty(parent)  # Allow relative paths
                        mkpath(build_dir)  # Use mkpath instead of mkdir
                    else
                        error("Parent directory '$parent' does not exist. Aborting...")
                    end
                end
                config[:build_dir] = abspath(build_dir)  # Store absolute path
            end
        elseif arg == "--force"
            config[:overwrite_target] = true
        elseif arg == "--debug"
            config[:compress] = false
            config[:adhoc_signing] = true
            config[:windowed] = false
        elseif arg == "--target-name"
            config[:target_name] = args[i + 1]
        elseif arg == "--adhoc-signing"
            config[:adhoc_signing] = true
        elseif arg == "--target-arch"
            i += 1
            if i > length(args)
                error("--target-arch requires a value")
            end
            config[:target_arch] = Symbol(args[i])
        elseif arg == "--target-bundle"
            i += 1
            if i > length(args)
                error("--target-bundle requires a value")
            end
            if args[i] == "all"
                push!(config[:target_bundle], :msix, :dmg, :snap)
            else
                push!(config[:target_bundle], Symbol(args[i]))
            end
        else
            @warn "Unknown argument: $arg"
        end
        i += 1
    end

    # Set default platform if none specified
    if isempty(config[:target_bundle])
        if Sys.isapple()
            push!(config[:target_bundle], :dmg)
        elseif Sys.islinux()
            push!(config[:target_bundle], :snap)
        elseif Sys.iswindows()
            push!(config[:target_bundle], :msix)
        else
            error("Could not detect platform. Specify manually with --target-bundle={msix|dmg|snap|all}")
        end
    end

    # Set default build directory if not specified
    if isnothing(config[:build_dir])
        config[:build_dir] = mktempdir()
    end
    
    return config
end

function print_help()
    println("""
    Usage: julia --project=meta meta/build.jl [OPTIONS]
    
    Options:
      --build-dir DIR                   Build directory (default: ./build)
                                        Use '@temp' for temporary directory
      --adhoc-signing                   Enable ad-hoc code signing (macOS/Windows)
      --target-arch ARCH                Target architecture (default: current system)
      --target-bundle={dmg|snap|msix|all}
                                        Build for specific platform(s) (default: current)
                                        Can be specified multiple times
      -h, --help                        Show this help message
    
    Examples:
      julia --project=meta meta/build.jl --target-bundle=all
      julia --project=meta meta/build.jl --build-dir=@temp 
      julia --project=meta meta/build.jl --target-bundle=snap --target-bundle=msix
      julia --project=meta meta/build.jl --target-arch=aarch64 --target-bundle=dmg
    
    Note: Options marked with * indicate the default value.
    """)
end
