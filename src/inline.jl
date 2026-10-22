const BINARY_TARGETS = Dict(
    # meta/icon.svg is not listed: there is no default SVG to inline
    "meta/icon.png"           => "icon.png",
    "meta/msix/resources.pri" => "msix/resources.pri",
)

const TEMPLATE_TARGETS = Dict(
    ".gitlab-ci.yml"                     => "workflows/GitLab.yml",
    ".github/workflows/Release.yml"      => "workflows/GitHub.yml",
    "meta/startup.jl"                    => "startup.jl",
    "meta/msix/AppxManifest.xml"         => "msix/AppxManifest.xml",
    "meta/msix/MSIXAppInstallerData.xml" => "msix/MSIXAppInstallerData.xml",
    "meta/dmg/Info.plist"                => "dmg/Info.plist",
    "meta/dmg/Entitlements.plist"        => "dmg/Entitlements.plist",
    "meta/dmg/DS_Store.toml"             => "dmg/DS_Store.toml",
    "meta/snap/snap.yaml"                => "snap/snap.yaml",
    "meta/snap/main.desktop"             => "snap/main.desktop",
    "meta/snap/configure.sh"             => "snap/configure.sh",
    "meta/appimage/AppRun.sh"            => "appimage/AppRun.sh",
)

# Each generator is called as f(project_dir, destination, preferences)
const GENERATED_TARGETS = Dict{String,Function}(
    "meta/msix/Assets" => function (project_dir, destination, preferences)
        msix = MSIX(project_dir; preferences)
        IconTools.msix_icons(IconTools.load(msix.icon), destination; msix.store_icon_plate)
    end,

    "meta/msix/certificate.pfx" => (_, destination, preferences) ->
        generate_windows_signing_certificate(destination; publisher = preferences["msix"]["publisher"]),

    "meta/dmg/icon.icns" => function (project_dir, destination, preferences)
        dmg = DMG(project_dir; preferences)
        IconTools.toicns(IconTools.load(dmg.icon), destination)
    end,

    "meta/dmg/DS_Store" => function (project_dir, destination, preferences)
        dmg = DMG(project_dir; preferences)
        install_dsstore(dmg.dsstore, destination; dmg.parameters)
    end,

    "meta/dmg/certificate.pfx" => (_, destination, _) ->
        generate_macos_signing_certificate(destination),

    "meta/snap/icon.png" => function (project_dir, destination, preferences)
        snap = Snap(project_dir; preferences)
        icon = IconTools.toicon(IconTools.load(snap.icon), 512)
        IconTools.save(destination, icon)
    end,
)

function get_template_parameters(project_dir, target; preferences = get_extended_preferences(project_dir))
    startswith(target, "meta/msix/")     && return MSIX(project_dir; preferences).parameters # I could do update_msix_parameters!(parameters; preferences) and etc
    startswith(target, "meta/snap/")     && return Snap(project_dir; preferences).parameters
    startswith(target, "meta/dmg/")      && return DMG(project_dir; preferences).parameters
    startswith(target, "meta/appimage/") && return AppImage(project_dir; preferences).parameters
    return get_bundle_parameters(preferences)
end

"""
    inline(project_dir, target; preferences = nothing, force = false, render = true)

Copy, render or generate `target` into `project_dir` so it can be customised.
Templates are rendered with `preferences` unless `render = false`, in which case
the raw template is copied. `preferences` is required when `render = true` and
for generated targets.
"""
function inline(project_dir, target; preferences = nothing, force = false, render = true)

    @assert !render || !isnothing(preferences) "preferences must be provided when render = true"

    destination = joinpath(project_dir, target)

    if ispath(destination)
        force || error("$destination already exists; pass `force = true` to overwrite it")
        rm(destination; recursive = true)
    end

    mkpath(dirname(destination))

    if haskey(BINARY_TARGETS, target)
        cp(joinpath(DEFAULT_DIR, BINARY_TARGETS[target]), destination)

    elseif haskey(TEMPLATE_TARGETS, target)
        source = joinpath(DEFAULT_DIR, TEMPLATE_TARGETS[target])
        if render
            parameters = get_template_parameters(project_dir, target; preferences)
            install(source, destination; parameters)
        else
            cp(source, destination)
        end

    elseif haskey(GENERATED_TARGETS, target)
        isnothing(preferences) && error("generating $target requires preferences")
        GENERATED_TARGETS[target](project_dir, destination, preferences)
    else
        known = sort!(collect(keys(BINARY_TARGETS) ∪ keys(TEMPLATE_TARGETS) ∪ keys(GENERATED_TARGETS)))
        error("Unknown target $target. Available targets:\n  " * join(known, "\n  "))
    end

    return destination
end

# Command-line entry point: build preferences from `-D...` arguments
function inline(project_dir, target, args::AbstractVector{<:AbstractString}; kwargs...)
    _, preference_overrides = parse_build_args(args)
    preferences = get_extended_preferences(project_dir; preference_overrides)
    return inline(project_dir, target; preferences, kwargs...)
end
