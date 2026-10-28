import .PrefTools: PreferenceStatus, PreferenceEntry

format_value(v::AbstractVector) = "[" * join(map(format_value, v), ", ") * "]"
format_value(v) = repr(v)


function print_preferences(io::IO, entries::AbstractVector{PreferenceEntry})
    missing_entries = filter(e -> e.status == PreferenceStatus.ERROR && isnothing(e.value), entries)
    value_entries   = filter(e -> !(e.status == PreferenceStatus.ERROR && isnothing(e.value)), entries)

    width = maximum(e -> length(e.key), value_entries; init = 0)

    for e in value_entries
        marker = e.status == PreferenceStatus.ERROR    ? "! " :
                 e.status == PreferenceStatus.INFERRED ? "* " : "  "
        line = string(marker, rpad(e.key, width), " = ", format_value(e.value))

        if e.status == PreferenceStatus.ERROR
            printstyled(io, line; color = :red)
        elseif e.status == PreferenceStatus.EXPLICIT
            print(io, line)
        else
            printstyled(io, line; color = :light_black)
        end
        println(io)
    end

    if !isempty(missing_entries)
        println(io)
        printstyled(io, "! Could not be inferred:\n"; color = :red)
        print_wrapped(io, [e.key for e in missing_entries]; indent = 4, color = :red)
    end
end

# Print words separated by ", ", wrapping lines at the terminal width
function print_wrapped(io::IO, words; indent = 0, color = :normal)
    max_width = displaysize(io)[2]
    pad = " "^indent
    line = pad

    for (i, word) in enumerate(words)
        piece = i < length(words) ? word * ", " : word
        if length(line) + length(piece) > max_width && line != pad
            printstyled(io, rstrip(line), '\n'; color)
            line = pad
        end
        line *= piece
    end
    printstyled(io, line, '\n'; color)
end


print_preferences(io::IO, preferences::Dict; kwargs...) =
    print_preferences(io, preferences_status(preferences; kwargs...))

print_preferences(preferences::Dict; kwargs...) = print_preferences(stdout, preferences; kwargs...)

function print_preferences(io::IO, project_dir; defines = Pair{String, Any}[])

    entries = preferences_status(project_dir; defines)
    print_preferences(io, entries)

    return
end

print_preferences(project_dir) = print_preferences(stdout, project_dir)

const DEFAULT_DIR = joinpath(dirname(@__DIR__), "recipes")

function issubpath(path, parent)
    p = splitpath(abspath(path))
    q = splitpath(abspath(parent))
    return length(p) >= length(q) && p[1:length(q)] == q
end

isoverride(path) = !isnothing(path) && !issubpath(path, DEFAULT_DIR)
isoverride(path::Verbatim) = isoverride(path.path)

isgenerated_asset(path) = true  #basename(path) in ("icon.png", "icon.svg")
isgenerated_asset(::Verbatim) = false


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

    # It is harder to break this one
    preferences = get(TOML.parsefile(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml")), "AppBundler", Dict{String,Any}())
    apply_defaults!(preferences, project_dir)

    msix = MSIX(project_dir; preferences)
    dmg = DMG(project_dir; preferences)
    snap = Snap(project_dir; preferences)
    appimage = AppImage(project_dir; preferences)

    return (
        "meta" => (
            "icon.svg" => icon_override && is_svg,
            "icon.png" => icon_override && !is_svg,
            "startup.jl" => isfile(joinpath(project_dir, "meta", "startup.jl")),
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
                "DS_Store.toml" => isoverride(dmg.dsstore) && !isgenerated_asset(dmg.dsstore),
                "DS_Store" => isgenerated_asset(dmg.dsstore) ? basename(dmg.dsstore) : isoverride(dmg.dsstore),
                "certificate.pfx" => isnothing(dmg.pfx_cert) ? "" : isoverride(dmg.pfx_cert),
            ),
            "snap" => (
                "icon.png" => isgenerated_asset(snap.icon) ? basename(snap.icon) : isoverride(snap.icon),
                "snap.yaml" => isoverride(snap.snap_config),
                "main.desktop" => isoverride(snap.desktop_launcher),
                "configure.sh" => isoverride(snap.configure_hook),
            ),
            "appimage" => (
                "AppRun.sh" => isoverride(appimage.apprun),
            ),
        ),
        ".github/workflows/Release.yml" => isfile(joinpath(project_dir, ".github/workflows/Release.yml")),
        ".gitlab-ci.yml" => isfile(joinpath(project_dir, ".gitlab-ci.yml"))
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
