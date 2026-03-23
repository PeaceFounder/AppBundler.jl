import TOML

import LibGit2
using Preferences

function (@main)(ARGS)

    if ARGS[1] == "build"

        old_project = Base.ACTIVE_PROJECT[]
        push!(Base.LOAD_PATH, pkgdir(AppBundler)) # needed for reading LocalPreferences.toml when AppBundler is loaded as project

        try
            Base.ACTIVE_PROJECT[] = joinpath(realpath(ARGS[2]))
            main_build(ARGS[3:end]; sources_dir = realpath(ARGS[2]))
        finally
            pop!(Base.LOAD_PATH)
            Base.ACTIVE_PROJECT[] = old_project
        end

    elseif ARGS[1] == "--help"
        println("Use the command as `appbundler [build|instantiate] [args]`.")

    else

        error("Got unsupported command $(ARGS[1]). See `--help` for available commands.")

    end

    return 0
end

suffix(msix::MSIX) = msix.compress ? ".msix" : ""
suffix(dmg::DMG) = dmg.compress ? ".dmg" : ""
suffix(snap::Snap) = snap.compress ? ".snap" : ""

function canonical_target_name(spec::Union{MSIX, DMG, Snap})
    version = spec.parameters["APP_VERSION"]
    app_name = spec.parameters["APP_NAME"]
    return "$(app_name)-$version-$(spec.arch)"
end

function main_build(ARGS; sources_dir)

    config, preferences = parse_args(ARGS)

    target_arch = config[:target_arch]
    target_bundle = config[:target_bundle]
    build_dir = config[:build_dir]
    selfsign = config[:selfsign]
    compress = config[:compress]
    windowed = config[:windowed]
    overwrite_target = config[:overwrite_target]
    password = config[:password]

    bundler = preferences["bundler"]

    if bundler == "juliaimg"

        if preferences["juliaimg_selective_assets"]
            remove_sources = true
            asset_spec = Resources.extract_asset_spec(sources_dir) 
        else
            remove_sources = false
            asset_spec = Dict{Symbol, Vector{String}}()
        end

        spec = JuliaImgBundle(sources_dir; 
                              precompile = preferences["juliaimg_precompile"],
                              incremental = preferences["juliaimg_incremental"],
                              sysimg_packages = preferences["juliaimg_sysimg"],
                              remove_sources,
                              asset_spec
                              ) 
        
    elseif bundler == "juliac"

        asset_spec = Resources.extract_asset_spec(sources_dir)
        spec = JuliaCBundle(sources_dir; trim = preferences["juliac_trim"], asset_spec) 

    else

        error("Got unsupported bundler type $bundler")

    end

    function target_path(spec)
        if !isnothing(config[:target_name])
            name = config[:target_name]
        else
            name = canonical_target_name(spec)
        end
        joinpath(build_dir, name * suffix(spec))
    end

    if :msix == target_bundle

        msix = MSIX(sources_dir; windowed, compress, selfsign, arch = target_arch, preferences)

        if selfsign
            password = ""
        elseif isnothing(msix.pfx_cert)
            error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
        elseif isnothing(password)
            print("Type in certificate password:")
            password = readline() |> strip
        end
        
        bundle(spec, msix, target_path(msix); force = overwrite_target, password)

    elseif :dmg == target_bundle

        dmg = DMG(sources_dir; windowed, selfsign, arch = target_arch, preferences)

        if selfsign
            password = ""
        elseif isnothing(dmg.pfx_cert)
            error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
        elseif isnothing(password)
            print("Type in certificate password:")
            password = readline() |> strip
        end

        bundle(spec, dmg, target_path(dmg); force = overwrite_target, password)

    elseif :snap == target_bundle

        snap = Snap(sources_dir; windowed, arch = target_arch, preferences)
        bundle(spec, snap, target_path(snap); force = overwrite_target)

    else
        error("Got unsupported bundle type $target_bundle")
    end

    return
end


function get_project_name(project_toml)

    toml_dict = TOML.parsefile(project_toml)
    if haskey(toml_dict, "name") 
        return toml_dict["name"]
    else
        return nothing
    end
end

function get_module_name(project_toml)

    project_name = get_project_name(project_toml)

    if !isnothing(project_name) && isfile(joinpath(dirname(project_toml), "src", project_name * ".jl"))
        return project_name
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

function get_bundle_parameters!(parameters::Dict{String, Any}, project_toml; preferences = preferences())

    # The parameter resolution can differ depending on what is being bundled. 
    # For instance MODULE_NAME is Julia specific only.

    if preferences["juliaimg_mainless"]
        project_name = get_project_name(project_toml)
        app_name = get(preferences, "app_name", project_name)
    else
        module_name = get_module_name(project_toml)
        parameters["MODULE_NAME"] = module_name
        app_name = get(preferences, "app_name", module_name) 
    end

    parameters["APP_NAME"] = lowercase(join(split(app_name, " "), "-"))

    parameters["APP_DISPLAY_NAME"] = get(preferences, "app_display_name", get(preferences, "app_name", app_name))

    parameters["APP_VERSION"] = get_project_version(project_toml)
    parameters["BUILD_NUMBER"] = get(preferences,"build_number", commit_count(dirname(project_toml)))
    
    parameters["APP_SUMMARY"] = preferences["app_summary"]
    parameters["APP_DESCRIPTION"] = preferences["app_description"]
    
    parameters["BUNDLE_IDENTIFIER"] = get(preferences, "bundle_identifier", "org.appbundler." * parameters["APP_NAME"])

    parameters["PUBLISHER_DISPLAY_NAME"] = preferences["publisher_name"]

    return parameters
end

# ToDo: Revise this function for accepting values that contain " "
# ToDo: Add tests for this funciton
function normalize_args(args)
    normalized = String[]
    for arg in args
        if startswith(arg, "--") && contains(arg, '=')
            flag, value = split(arg, '=', limit=2)
            push!(normalized, flag)
            push!(normalized, strip(value, ['"', '\'']))
        elseif startswith(arg, "-D")
            push!(normalized, "-D")
            push!(normalized, arg[3:end])
        else
            push!(normalized, arg)
        end
    end
    return normalized
end

function parse_args(raw_args)

    args = normalize_args(raw_args)

    config = Dict()
    preference_overrides = []

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
        elseif arg == "-D"
            i += 1
            push!(preference_overrides, args[i])
        elseif arg == "--force"
            config[:overwrite_target] = true
        elseif arg == "--debug"
            config[:compress] = false
            config[:selfsign] = true
            config[:windowed] = false
        elseif arg == "--target-name"
            i += 1
            config[:target_name] = args[i]
        elseif arg == "--selfsign"
            config[:selfsign] = true
        elseif arg == "--password"
            i += 1
            config[:password] = args[i] |> strip
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
            config[:target_bundle] = Symbol(args[i])
        else
            @warn "Unknown argument: $arg"
        end
        i += 1
    end

    preference_overrides_dict = TOML.parse(join(preference_overrides, "\n"))
    preferences = merge(Base.get_preferences()["AppBundler"], preference_overrides_dict)

    # Default values
    defaults = Dict(
        :build_dir => mktempdir(),  # Use nothing to distinguish "not set" from ""
        :compress => preferences["compress"],
        :windowed => preferences["windowed"],
        :selfsign => preferences["selfsign"],
        :target_arch => Sys.ARCH,
        :target_bundle => Sys.islinux() ? :snap : Sys.isapple() ? :dmg : Sys.iswindows() ? :msix : error("Bundling for current platform is unsupported"),
        :target_name => nothing,
        :overwrite_target => preferences["overwrite_target"],
        :password => nothing
    )

    return merge(defaults, config), preferences
end


const HELP_TEXT = """
Usage: appbundler build <project_dir> [OPTIONS]

Arguments:
  <project_dir>                     Path to the Julia project to bundle

Options:
  --build-dir DIR                   Output directory for the bundle
                                    (default: temporary directory)
                                    Use '@temp' to explicitly request a temp dir
  --target-bundle {dmg|snap|msix}   Package format to produce
                                    (default: platform native — dmg on macOS,
                                    snap on Linux, msix on Windows)
  --target-arch {x86_64|aarch64}    Target CPU architecture
                                    (default: current system architecture)
  --target-name NAME                Override the output file/directory name
                                    (default: derived from app name and version)
  --selfsign                        Sign the bundle with a self-signed certificate
                                    (macOS / Windows; skips password prompt)
  --password PASS                   Password for the signing certificate
                                    (prompted interactively if omitted)
  --force                           Overwrite an existing bundle at the target path
  --debug                           Shorthand for --selfsign + uncompressed,
                                    console-visible build; useful for quick iteration
  -DKEY=VALUE                       Override a LocalPreferences.toml preference,
                                    e.g. -Dbundler="juliac"
  -h, --help                        Show this help message

Examples:
  appbundler build .
  appbundler build . --build-dir=build --force
  appbundler build . --build-dir=@temp --debug
  appbundler build . --target-bundle=snap --target-arch=aarch64
  appbundler build . --selfsign --password=secret
  appbundler build . -Dbundler="juliac" -Djuliac_trim=true
"""

function print_help()
    println(HELP_TEXT)
end
