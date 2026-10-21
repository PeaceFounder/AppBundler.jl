flat_keys(d) = Set(string(k) for k in keys(ArgTools.flatten_schema(d)))

function load_preferences_section(path; section = "AppBundler")
    isfile(path) || return Dict{String,Any}()
    return get(TOML.parsefile(path), section, Dict{String,Any}())
end

# Keys set in the project's LocalPreferences.toml or on the command line
function explicit_preference_keys(project_dir, preference_overrides)
    keys_project = isnothing(project_dir) ? Set{String}() :
        flat_keys(load_preferences_section(joinpath(project_dir, "LocalPreferences.toml")))
    return keys_project ∪ flat_keys(preference_overrides)
end

# Keys absent from AppBundler's static defaults and not set explicitly
function inferred_preference_keys(final_flat, explicit_keys)
    defaults = load_preferences_section(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml"))
    return setdiff(keys(final_flat), flat_keys(defaults), explicit_keys)
end

module PreferenceStatus
    @enum T EXPLICIT INFERRED DEFAULT
end

const PreferenceEntry = @NamedTuple{key::String, value::Any, status::PreferenceStatus.T}

"""
    preferences_status(preferences; project_dir = nothing, preference_overrides = Dict())

Return a vector of `(key, value, status)` entries, sorted by status and then key, where status is
- `PreferenceStatus.EXPLICIT` : set in the project's LocalPreferences.toml or on the command line
- `PreferenceStatus.INFERRED` : not among AppBundler's static defaults and not set explicitly
- `PreferenceStatus.DEFAULT`  : taken from AppBundler's static defaults
"""
function preferences_status(preferences::Dict; project_dir = nothing, preference_overrides = Dict())
    preferences = get(preferences, "AppBundler", preferences)
    final_flat  = ArgTools.flatten_schema(preferences)

    explicit_keys = explicit_preference_keys(project_dir, preference_overrides)
    inferred_keys = inferred_preference_keys(final_flat, explicit_keys)

    status(k) = k in explicit_keys ? PreferenceStatus.EXPLICIT :
                k in inferred_keys ? PreferenceStatus.INFERRED :
                                     PreferenceStatus.DEFAULT

    entries = PreferenceEntry[(key = string(k), value = v, status = status(k)) for (k, v) in final_flat]
    return sort!(entries; by = e -> (e.status, e.key))
end

function print_preferences(io::IO, entries::AbstractVector{PreferenceEntry})
    width = maximum(e -> length(e.key), entries; init = 0)

    for e in entries
        marker = e.status == PreferenceStatus.INFERRED ? "* " : "  "
        line = string(marker, rpad(e.key, width), " = ", repr(e.value))
        if e.status == PreferenceStatus.EXPLICIT
            println(io, line)
        else
            printstyled(io, line; color = :light_black)
            println(io)
        end
    end
end

print_preferences(io::IO, preferences::Dict; kwargs...) =
    print_preferences(io, preferences_status(preferences; kwargs...))

print_preferences(preferences::Dict; kwargs...) = print_preferences(stdout, preferences; kwargs...)

function print_preferences(io::IO, ARGS::AbstractVector{<:AbstractString}; project_dir = nothing)
    config, preference_overrides = parse_build_args(ARGS)
    extended_preferences = get_extended_preferences(project_dir; preference_overrides)
    print_preferences(io, extended_preferences; project_dir, preference_overrides)
    return
end

print_preferences(ARGS::AbstractVector{<:AbstractString}; kwargs...) =
    print_preferences(stdout, ARGS; kwargs...)


const DEFAULT_DIR = joinpath(dirname(@__DIR__), "recipes")

function issubpath(path, parent)
    p = splitpath(abspath(path))
    q = splitpath(abspath(parent))
    return length(p) >= length(q) && p[1:length(q)] == q
end

isoverride(path) = !isnothing(path) && !issubpath(path, DEFAULT_DIR)

isgenerated_asset(path) = basename(path) in ("icon.png", "icon.svg")

"""
    override_status(project_dir)

Return a nested tuple of `name => status` pairs where status is
- `true`   : overridden by the project
- `false`  : default from recipes
- `String` : generated from the named source (empty string = generated, no source shown)
- `Tuple`  : a nested directory
"""
function override_status(project_dir)
    # SVG takes precedence
    icon_path = get_path([joinpath(project_dir, "meta"), DEFAULT_DIR], ["icon.svg", "icon.png"])
    icon_override = isoverride(icon_path)
    is_svg = basename(icon_path) == "icon.svg"

    msix = MSIX(project_dir)
    dmg = DMG(project_dir)
    snap = Snap(project_dir)
    appimage = AppImage(project_dir)

    return (
        "meta" => (
            "icon.svg" => icon_override && is_svg,
            "icon.png" => icon_override && !is_svg,
            "msix" => (
                "Assets" => isgenerated_asset(msix.icon) ? basename(msix.icon) : isoverride(msix.icon),
                "AppxManifest.xml" => isoverride(msix.appxmanifest),
                "resources.pri" => isoverride(msix.resources_pri),
                "MSIXAppInstallerData.xml" => isoverride(msix.msixinstallerdata),
                "certificate.pfx" => isnothing(msix.pfx_cert) ? "" : isoverride(msix.pfx_cert),
            ),
            "dmg" => (
                "icon.icns" => isgenerated_asset(dmg.icon) ? basename(dmg.icon) : isoverride(dmg.icon),
                "Info.plist" => isoverride(dmg.info_config),
                "Entitlements.plist" => isoverride(dmg.entitlements),
                "DS_Store.toml" => isoverride(dmg.dsstore),
                "certificate.pfx" => isnothing(dmg.pfx_cert) ? "" : isoverride(dmg.pfx_cert),
            ),
            "snap" => (
                "icon.png" => isgenerated_asset(snap.icon) && basename(dirname(snap.icon)) != "snap" ?
                              basename(snap.icon) : isoverride(snap.icon),
                "snap.yaml" => isoverride(snap.snap_config),
                "main.desktop" => isoverride(snap.desktop_launcher),
                "configure.sh" => isoverride(snap.configure_hook),
            ),
            "appimage" => (
                "AppRun.sh" => isoverride(appimage.apprun),
            ),
        ),
    )
end

isoverridden(value) = value === true || (value isa Tuple && any(((_, v),) -> isoverridden(v), value))

function print_overrides(io::IO, entries::Tuple; indent::Int = 0)
    for (key, value) in entries
        generated = value isa AbstractString
        prefix = indent == 0 ? "" : " "^(indent - 2) * (generated ? "* " : "  ")

        if value isa Tuple
            if isoverridden(value)
                println(io, prefix, key, "/")
            else
                printstyled(io, prefix, key, "/"; color = :light_black)
                println(io)
            end
            print_overrides(io, value; indent = indent + 2)
        elseif value === true
            println(io, prefix, key)
        else
            printstyled(io, prefix, key; color = :light_black)
            if generated && !isempty(value)
                if get(io, :color, false)
                    print(io, "\e[2;90m  [source = ", value, "]\e[0m")
                else
                    print(io, "  [source = ", value, "]")
                end
            end
            println(io)
        end
    end
end

print_overrides(io::IO, entry::Pair; kwargs...) = print_overrides(io, (entry,); kwargs...)
print_overrides(entries::Union{Tuple,Pair}; kwargs...) = print_overrides(stdout, entries; kwargs...)

print_overrides(io::IO, project_dir::AbstractString) = print_overrides(io, override_status(project_dir))
print_overrides(project_dir::AbstractString) = print_overrides(stdout, project_dir)


function print_status(io::IO, project_dir; args = [])

    println(io, "LocalPreferences.toml:") # may need to look into the case when there are no overrides
    print_preferences(io, args; project_dir)
    print_overrides(io, project_dir)

end

print_status(project_dir; args = []) = print_status(stdout, project_dir; args)
