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
    # meta/snap/configure.sh is not listed; there is no default to inline
    "meta/appimage/AppRun.sh"            => "appimage/AppRun.sh",
)

# Each generator is called as f(project_dir, destination, preferences)
const GENERATED_TARGETS = Dict{String,Function}(
    "meta/msix/Assets" => function (project_dir, destination, preferences)
        msix = MSIX(project_dir; preferences)
        IconTools.msix_icons(IconTools.load(msix.icon), destination; msix.store_icon_plate);
    end,

    "meta/msix/certificate.pfx" => (_, destination, preferences) ->
        generate_windows_signing_certificate(destination; publisher = preferences["msix"]["publisher"]),

    "meta/dmg/icon.icns" => function (project_dir, destination, preferences)
        dmg = DMG(project_dir; preferences)
        IconTools.toicns(IconTools.load(dmg.icon), destination);
    end,

    "meta/dmg/DS_Store" => function (project_dir, destination, preferences)
        dmg = DMG(project_dir; preferences)
        install_dsstore(dmg.dsstore, destination; dmg.parameters);
    end,

    "meta/dmg/certificate.pfx" => (_, destination, _) ->
        generate_macos_signing_certificate(destination),

    "meta/snap/icon.png" => function (project_dir, destination, preferences)
        snap = Snap(project_dir; preferences)
        icon = IconTools.toicon(IconTools.load(snap.icon), 512)
        IconTools.save(destination, icon);
    end,
)

function get_template_parameters(project_dir, target; defines = [])

    preferences = load_preferences(project_dir; defines)["AppBundler"]

    startswith(target, "meta/msix/")     && return MSIX(project_dir; preferences).parameters 
    startswith(target, "meta/snap/")     && return Snap(project_dir; preferences).parameters
    startswith(target, "meta/dmg/")      && return DMG(project_dir; preferences).parameters
    startswith(target, "meta/appimage/") && return AppImage(project_dir; preferences).parameters
    return get_bundle_parameters(preferences)
end


# toml_line(key, value) = key * chopprefix(rstrip(sprint(TOML.print, Dict("x" => value))), "x")

# # Insert `line` at the end of the `[table]` block; `nothing` if the file has no such header
# function insert_line(text, table, line)
#     block = Regex("^[ \\t]*\\[" * replace(table, "." => "\\.") * "\\][^\\n]*(?:\\n(?![ \\t]*\\[)[^\\n]*)*", "m")
#     occursin(block, text) || return nothing
#     return replace(text, block => function (b)
#         body = rstrip(b)
#         body * "\n" * match(r"^[ \t]*", b).match * line * chopprefix(b, body)
#     end; count = 1)
# end

# """
#     inline_preferences(destination, defines; section = "AppBundler", schema = LOCAL_PREFERENCES_SCHEMA)

# Add `defines`, the `key => text` pairs from `ArgTools.parse_options`, to `[section]` of the TOML
# file at `destination`. Values are coerced against `schema`, and each new line is inserted into the
# table block it belongs to, leaving the rest of the file untouched. Errors if any key is already set.
# """
# function inline_preferences(destination, defines; force = true, section = "AppBundler", schema = LOCAL_PREFERENCES_SCHEMA)
#     defines = ArgTools.coerce(defines, schema)

#     text = isfile(destination) ? read(destination, String) : ""
#     current = flatten_schema(get(TOML.parse(text), section, Dict{String,Any}()))

#     already = sort!([key for (key, _) in defines if haskey(current, key)])
#     isempty(already) || error("$destination already sets " * join(already, ", "))

#     for (key, value) in defines
#         parts = split(key, '.')
#         updated = nothing
#         for n in length(parts)-1:-1:0          # deepest existing table header on the key's path
#             table = join([section; parts[1:n]], '.')
#             updated = insert_line(text, table, toml_line(join(parts[n+1:end], '.'), value))
#             isnothing(updated) || break
#         end
#         text = something(updated,
#             (isempty(strip(text)) ? "" : rstrip(text) * "\n\n") * "[$section]\n" * toml_line(key, value) * "\n")
#     end

#     # Safety net: the edited text must parse, and every value must read back where it was meant to land
#     written = flatten_schema(get(TOML.parse(text), section, Dict{String,Any}()))
#     misplaced = [key for (key, value) in defines if get(written, key, nothing) != value]
#     isempty(misplaced) || error("Could not place " * join(misplaced, ", ") * " in $destination")

#     write(destination, text)
#     return destination
# end


"""
    inline(project_dir, target; preferences = nothing, force = false, render = true)

Copy, render or generate `target` into `project_dir` so it can be customised.
Templates are rendered with `preferences` unless `render = false`, in which case
the raw template is copied. `preferences` is required when `render = true` and
for generated targets.
"""
function inline(project_dir, target; force = false, render = false, defines = [], verbose = false, destination = joinpath(project_dir, target))

    if target == "LocalPreferences.toml" 
        defines = ArgTools.coerce(defines, LOCAL_PREFERENCES_SCHEMA)
        PrefTools.inline_preferences(destination, defines; section = "AppBundler")
        return
    else
        if ispath(destination)
            force || error("$destination already exists; pass `force = true` to overwrite it")
            rm(destination; recursive = true)
        end
    end

    mkpath(dirname(destination))

    if haskey(BINARY_TARGETS, target)
        cp(joinpath(DEFAULT_DIR, BINARY_TARGETS[target]), destination)

    elseif haskey(TEMPLATE_TARGETS, target)
        source = joinpath(DEFAULT_DIR, TEMPLATE_TARGETS[target])
        if render
            parameters = get_template_parameters(project_dir, target; defines)

            if verbose
                println("-------------- TEMPLATE PARAMETERS -----------")
                for (key, value) in parameters
                    println("$key = $(repr(value))")
                end
                println("----------------------------------------------")
            end

            install(source, destination; parameters)
        else
            cp(source, destination)
        end

    elseif haskey(GENERATED_TARGETS, target)
        return GENERATED_TARGETS[target](project_dir, destination, load_preferences(project_dir; defines)["AppBundler"])
    else
        known = sort!(collect(keys(BINARY_TARGETS) ∪ keys(TEMPLATE_TARGETS) ∪ keys(GENERATED_TARGETS)))
        error("Unknown target $target. Available targets:\n  " * join(known, "\n  "))
    end

    return
end
