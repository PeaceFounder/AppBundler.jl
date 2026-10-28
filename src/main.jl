import TOML
import LibGit2

function (@main)(ARGS)

    if length(ARGS) == 0 
        error("No command provided. See `--help` for available commands.")
    end

    command = ARGS[1]

    if command in ["--help", "-h"]

        # one may want to print a generic help here and then point user down to
        # build --help and etc for concrete information
        print_help()

    elseif command == "build"

        if length(ARGS) < 2
            error("No project path provided for `build` command. See `build --help` for usage.")
        end

        #main_build(ARGS[3:end]; sources_dir = realpath(ARGS[2]))
        main_build(realpath(ARGS[2]), ARGS[3:end])

    elseif command == "inline"
        
        main_inline(realpath(ARGS[2]), ARGS[3], ARGS[4:end])

    elseif command == "status"

        main_status(realpath(ARGS[2]), ARGS[3:end])

    else
        error("Unsupported command `$command`. See `--help` for available commands.")
    end

    return 0
end

suffix(msix::MSIX) = msix.compress ? ".msix" : ""
suffix(dmg::DMG) = dmg.compress ? ".dmg" : ""
suffix(snap::Snap) = snap.compress ? ".snap" : ""
suffix(appimage::AppImage) = appimage.compress ? ".AppImage" : ""

function canonical_target_name(spec::Union{MSIX, DMG, Snap, AppImage})
    version = spec.parameters["APP_VERSION"]
    app_name = spec.parameters["APP_NAME"]
    return "$(app_name)-$version-$(spec.arch)"
end


function main_status(project_dir, raw_args; io = stdout)

    args, defines = ArgTools.parse_options(raw_args; short_options = SHORT_OPTIONS)

    @assert isempty(defines) "Nonempty defins not supported"

    show_preferences = true
    show_files = true
    
    for (key, value) in args
    
        if key == "--help"
            print_help()
            exit(0)
        elseif key == "--preferences"
            show_files = false
        elseif key == "--files"
            show_preferences = false
        else
            @warn "Unknown argument: $key"
        end
    end

    if !show_preferences && !show_files       # no filter given → show everything
        show_preferences = show_files = true
    end

    if show_preferences
        println(io, "LocalPreferences.toml:") # may need to look into the case when there are no overrides
        print_preferences(io, project_dir)
    end

    if show_files 
        print_overrides(io, project_dir)
    end

    return
end


function main_inline(project_dir, target, raw_args::AbstractVector{<:AbstractString})

    args, defines = ArgTools.parse_options(raw_args; short_options = SHORT_OPTIONS)

    force = false
    render = false
    verbose = false

    for (option, value) in args
        if option == "--help"
            print_help()
            exit(0)
        elseif option == "--force"
            force = true
        elseif option == "--render"
            render = true
        elseif option == "--verbose"
            verbose = true
        else
            @warn "Unknown argument: $option"
        end
    end

    return inline(project_dir, target; defines, force, render, verbose)
end


function main_build(sources_dir, ARGS)

    config, defines = parse_build_args(ARGS)
    extended_preferences = load_preferences(sources_dir; defines)
    preferences = extended_preferences["AppBundler"]

    if config[:build_dir] == "@temp"
        build_dir = mktempdir()
    else
        build_dir = abspath(expanduser(config[:build_dir]))
        if !isdir(build_dir)
            parent = dirname(build_dir)
            if isdir(parent) || isempty(parent)  # Allow relative paths
                mkpath(build_dir)  # Use mkpath instead of mkdir
            else
                error("Parent directory '$parent' does not exist. Aborting...")
            end
        end
    end
        
    target_arch = config[:target_arch]
    target_bundle = config[:target_bundle]
    password = config[:password]

    # Theese could be substituted with preferences
    selfsign = preferences["selfsign"]
    skipsign = preferences["skipsign"]
    overwrite_target = preferences["overwrite_target"]
    msix2exe = preferences["msix"]["bootstrapper"]
    verbose = preferences["verbose"]

    bundler = preferences["bundler"]

    if bundler == "juliaimg"

        if preferences["juliaimg"]["selective_assets"]
            remove_sources = true
            asset_spec = Resources.extract_asset_spec(sources_dir; project_preferences=extended_preferences) 
        else
            remove_sources = false
            asset_spec = Dict{Symbol, Vector{String}}()
        end

        spec = JuliaImgBundle(sources_dir; 
                              precompile = preferences["juliaimg"]["precompile"],
                              incremental = preferences["juliaimg"]["incremental"],
                              sysimg_packages = preferences["juliaimg"]["sysimg"],
                              remove_sources,
                              asset_spec
                              ) 
        
    elseif bundler == "juliac"

        asset_spec = Resources.extract_asset_spec(sources_dir; project_preferences=extended_preferences)
        spec = JuliaCBundle(sources_dir; trim = preferences["juliac"]["trim"], asset_spec) 

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

        msix = MSIX(sources_dir; arch = target_arch, preferences)

        if selfsign || skipsign
            password = ""
        elseif isnothing(msix.pfx_cert)
            error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
        elseif isnothing(password)
            print("Type in certificate password:")
            password = readline() |> strip
        end
        
        target = target_path(msix)
        bundle(spec, msix, target; force = overwrite_target, password)

        if msix2exe # false by default because depends on external resources
            
            exespec = MSIX2EXE(sources_dir; preferences)
            repack(target, exespec, join((first(splitext(target)), ".exe")); force = overwrite_target)

        end

    elseif :dmg == target_bundle
        
        dmg = DMG(sources_dir; arch = target_arch, preferences)

        if selfsign || skipsign
            password = ""
        elseif isnothing(dmg.pfx_cert)
            error("No pfx certificate found and selfsign is disabled. Enable self signing with `--selfsign` or generate pfx certificates")
        elseif isnothing(password)
            print("Type in certificate password:")
            password = readline() |> strip
        end

        bundle(spec, dmg, target_path(dmg); force = overwrite_target, password, verbose)

    elseif :snap == target_bundle

        snap = Snap(sources_dir; arch = target_arch, preferences)
        bundle(spec, snap, target_path(snap); force = overwrite_target)

    elseif :appimage == target_bundle
        
        appimage = AppImage(sources_dir; arch = target_arch, preferences)
        bundle(spec, appimage, target_path(appimage); force = overwrite_target)

    else
        error("Got unsupported bundle type $target_bundle")
    end

    return
end


# Short options, mapped to their long form. Listed explicitly because a leading
# single dash is otherwise a value: `--password -secret` must keep -secret.
const SHORT_OPTIONS = Dict("-h" => "--help")

require(option, value) = value === nothing ? error("$option requires a value") : value
forbid(option, value)  = value === nothing || error("$option does not take a value, got '$value'")

function parse_build_args(raw_args::Vector{<:AbstractString}) 

    args, defines_raw = ArgTools.parse_options(raw_args; short_options = SHORT_OPTIONS)
    defines = ArgTools.coerce(defines_raw, LOCAL_PREFERENCES_SCHEMA)
    reverse!(defines)
    
    # Default values
    config = Dict(
        :build_dir => mktempdir(),  # Use nothing to distinguish "not set" from ""
        :target_arch => Sys.ARCH,
        :target_bundle => Sys.islinux() ? :snap : Sys.isapple() ? :dmg : Sys.iswindows() ? :msix : error("Bundling for current platform is unsupported"),
        :target_name => nothing,
        :password => nothing
    )

    for (option, value) in args
        if option == "--help"
            print_help()
            exit(0)
        elseif option == "--build-dir"
            config[:build_dir] = require(option, value)
        elseif option == "--target-name"
            config[:target_name] = require(option, value)
        elseif option == "--password"
            config[:password] = strip(require(option, value))
        elseif option == "--target-arch"
            config[:target_arch] = Symbol(require(option, value))
        elseif option == "--target-bundle"
            config[:target_bundle] = Symbol(require(option, value))
        elseif option == "--force"
            forbid(option, value)
            push!(defines, "overwrite_target" => true)
        elseif option == "--selfsign"
            forbid(option, value)
            push!(defines, "selfsign" => true)
        elseif option == "--skipsign"
            forbid(option, value)
            push!(defines, "skipsign" => true)
        elseif option == "--debug"
            forbid(option, value)
            push!(defines, "compress" => false)
            push!(defines, "selfsign" => true)
            push!(defines, "windowed" => false)
        else
            @warn "Unknown argument: $option"
        end
    end

    # This is propper as long as we don't consider lists
    unique!(first, defines)

    return config, defines
end


const HELP_TEXT = """
Usage: appbundler <command> <project_dir> [OPTIONS]

Commands:
  build <project_dir>               Bundle a Julia project as dmg, msix,
                                    snap or AppImage
  inline <project_dir> <target>     Write a default file into the project
                                    so it can be customized: a template,
                                    an icon, a generated asset or signing
                                    certificate, or LocalPreferences.toml.
                                    An unknown target lists all available
  status <project_dir>              Show active preferences and files that
                                    override the defaults

Build options:
  --target-bundle {dmg|msix|snap|appimage}
                                    Package format to produce
                                    (default: dmg on macOS, msix on Windows,
                                    snap on Linux)
  --target-arch {x86_64|aarch64}    Target CPU architecture
                                    (default: current system architecture)
  --build-dir DIR                   Output directory, created if missing
                                    (default: a new temporary directory;
                                    '@temp' requests one explicitly)
  --target-name NAME                Output name, without extension
                                    (default: <APP_NAME>-<APP_VERSION>-<arch>)
  --force                           Overwrite an existing bundle
  --selfsign                        Sign with a self-signed certificate
                                    (dmg, msix); no password needed
  --skipsign                        Do not sign the bundle (dmg, msix)
  --password PASS                   Password for the .pfx certificate
                                    (prompted for when needed and omitted)
  --debug                           Quick iteration build: --selfsign plus
                                    -Dcompress=false -Dwindowed=false
                                    (unpacked output, console visible)

Inline options:
  --force                           Overwrite the target if already present
  --render                          Fill in template parameters from the
                                    project preferences instead of copying
                                    the raw template
  --verbose                         Print the template parameters used
                                    by --render

Status options:
  --preferences                     Show only LocalPreferences.toml settings
  --files                           Show only overriding files

Common options:
  -DKEY=VALUE                       Override a LocalPreferences.toml entry
                                    (build, inline); nested keys use dots,
                                    e.g. -Djuliac.trim=true
  -h, --help                        Show this help message

Examples:
  appbundler build .
  appbundler build . --build-dir=build --force
  appbundler build . --target-bundle=appimage --target-arch=aarch64
  appbundler build . --password=secret
  appbundler build . -Dbundler="juliac" -Djuliac.trim=true
  appbundler build . --target-bundle=msix -Dmsix.bootstrapper=true

  appbundler inline . LocalPreferences.toml -Dbundler="juliac"
  appbundler inline . meta/snap/snap.yaml --render --verbose --force
  appbundler inline . meta/msix/certificate.pfx -Dmsix.publisher="CN=Me"
  appbundler inline . .github/workflows/Release.yml

  appbundler status .
  appbundler status . --files
"""

function print_help()
    println(HELP_TEXT)
end
