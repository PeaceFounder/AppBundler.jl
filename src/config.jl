import TOML

# ToDo: Adopt Preferences.toml
function get_bundle_parameters(project_toml)

    toml_dict = TOML.parsefile(project_toml)

    parameters = Dict{String, Any}()

    if haskey(toml_dict, "name") && isfile(joinpath(dirname(project_toml), "src", toml_dict["name"] * ".jl"))
        parameters["MODULE_NAME"] = toml_dict["name"]
    end

    app_name = haskey(toml_dict, "APP_NAME") ? toml_dict["APP_NAME"] : haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))
    parameters["APP_NAME"] = lowercase(join(split(app_name, " "), "-"))
    #parameters["APP_DIR_NAME"] = haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))
    #parameters["APP_VERSION"] = haskey(toml_dict, "version") ? toml_dict["version"] : "0.0.1"
    parameters["APP_VERSION"] = get(toml_dict, "version", "0.0.1")

    # Setting defaults
    parameters["APP_DISPLAY_NAME"] = app_name #parameters["APP_NAME"]
    parameters["APP_SUMMARY"] = "This is a default app summary"
    parameters["APP_DESCRIPTION"] = "A longer description of the app"
    parameters["WITH_SPLASH_SCREEN"] = "false"
    parameters["BUNDLE_IDENTIFIER"] = "org.appbundler." * lowercase(parameters["APP_NAME"])
    parameters["PUBLISHER"] = "CN=AppBundler"
    parameters["PUBLISHER_DISPLAY_NAME"] = "AppBundler"
    parameters["BUILD_NUMBER"] = 0
    parameters["RUNTIME_MODE"] = "SANDBOX"
    
    if haskey(toml_dict, "bundle")
        for (key, value) in toml_dict["bundle"]
            parameters[key] = string(value) # Mustache does not print false.
        end
    end

    parameters["APP_NAME_LOWERCASE"] = lowercase(parameters["APP_NAME"])

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
        :precompile => true,
        :incremental => false,
        :adhoc_signing => false,
        :target_arch => Sys.ARCH,
        :target_platforms => Symbol[]
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
        elseif arg == "--compiled-modules"
            i += 1
            if i > length(args)
                error("--compiled-modules requires a value")
            end
            value = args[i]
            if value == "yes"
                config[:precompile] = true
                config[:incremental] = false
            elseif value == "incremental"
                config[:precompile] = true
                config[:incremental] = true
            elseif value == "no"
                config[:precompile] = false
                config[:incremental] = false
            elseif value == "existing"
                config[:precompile] = false
                config[:incremental] = true
            else
                error("Unrecognized value '$value' for --compiled-modules. Use: yes|no|incremental|existing")
            end
        elseif arg == "--adhoc-signing"
            config[:adhoc_signing] = true
        elseif arg == "--target-arch"
            i += 1
            if i > length(args)
                error("--target-arch requires a value")
            end
            config[:target_arch] = Symbol(args[i])
        elseif arg == "--target-platform"
            i += 1
            if i > length(args)
                error("--target-platform requires a value")
            end
            if args[i] == "all"
                push!(config[:target_platforms], :linux, :macos, :windows)
            else
                push!(config[:target_platforms], Symbol(args[i]))
            end
        else
            @warn "Unknown argument: $arg"
        end
        i += 1
    end

    # Set default platform if none specified
    if isempty(config[:target_platforms])
        if Sys.isapple()
            push!(config[:target_platforms], :macos)
        elseif Sys.islinux()
            push!(config[:target_platforms], :linux)
        elseif Sys.iswindows()
            push!(config[:target_platforms], :windows)
        else
            error("Could not detect platform. Specify manually with --target-platform={linux|macos|windows|all}")
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
      --compiled-modules={yes*|no|incremental|existing}
                                        Control precompilation and incremental builds
                                        yes: precompile, no incremental (default)
                                        incremental: precompile with incremental
                                        no: no precompilation
                                        existing: use existing, no new precompilation
      --adhoc-signing                   Enable ad-hoc code signing (macOS/Windows)
      --target-arch ARCH                Target architecture (default: current system)
      --target-platform={linux|macos|windows|all}
                                        Build for specific platform(s) (default: current)
                                        Can be specified multiple times
      -h, --help                        Show this help message
    
    Examples:
      julia --project=meta meta/build.jl --target-platform=all
      julia --project=meta meta/build.jl --build-dir=@temp --compiled-modules=no
      julia --project=meta meta/build.jl --target-platform=linux --target-platform=windows
      julia --project=meta meta/build.jl --target-arch=aarch64 --target-platform=macos
    
    Note: Options marked with * indicate the default value.
    """)
end
