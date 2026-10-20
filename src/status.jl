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

function print_preferences(io::IO, preferences::Dict; project_dir = nothing, preference_overrides = Dict())

    preferences = get(preferences, "AppBundler", preferences)
    final_flat  = ArgTools.flatten_schema(preferences)

    explicit_keys = explicit_preference_keys(project_dir, preference_overrides)
    inferred_keys = inferred_preference_keys(final_flat, explicit_keys)

    print_preferences(io, final_flat, explicit_keys, inferred_keys)
end

print_preferences(preferences::Dict; kwargs...) = print_preferences(stdout, preferences; kwargs...)

function print_preferences(io::IO, final_flat::Dict, explicit_keys, inferred_keys)

    width = maximum(length, keys(final_flat); init = 0)

    function print_entry(key, marker; color = :normal, bold = false)
        line = string(marker, rpad(key, width), " => ", repr(final_flat[key]))
        printstyled(io, line, '\n'; color, bold)
    end

    all_keys = sort!(collect(keys(final_flat)))

    for key in all_keys
        key in explicit_keys && print_entry(key, "  "; bold = false)
    end
    for key in all_keys
        key in inferred_keys && print_entry(key, "* "; color = :light_black)
    end
    for key in all_keys
        key in explicit_keys || key in inferred_keys ||
            print_entry(key, "  "; color = :light_black)
    end
end


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

    assets = isgenerated_asset(msix.icon) ? basename(msix.icon) : isoverride(msix.icon)
    cert = isnothing(msix.pfx_cert) ? "" : isoverride(msix.pfx_cert)

    return (
        "icon.svg" => icon_override && is_svg,
        "icon.png" => icon_override && !is_svg,
        "msix" => (
            "Assets" => assets,
            "AppxManifest.xml" => isoverride(msix.appxmanifest),
            "resources.pri" => isoverride(msix.resources_pri),
            "MSIXAppInstallerData.xml" => isoverride(msix.msixinstallerdata),
            "certificate.pfx" => cert,
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

print_overrides(entries::Tuple; kwargs...) = print_overrides(stdout, entries; kwargs...)
print_overrides(project_dir::AbstractString) = print_overrides(stdout, override_status(project_dir))




# function issubpath(path, parent)
#     p = splitpath(abspath(path))
#     q = splitpath(abspath(parent))
#     return length(p) >= length(q) && p[1:length(q)] == q
# end

# issubpath(::Nothing, parent) = true


# function isgenerated_asset(icon_path)

#     if basename(icon_path) in ["icon.png", "icon.svg"]
#         return true
#     else
#         return false
#     end
# end


# (
# "icon.svg" => false,
# "icon.png" => false,
# "msix" => (
#     "Assets" => "icon.svg", # means it is generated from "icon.svg"
#     "AppxManifest.xml" => false,
#     "resources.pri" => false,
#     "MSIXAppInstallerData.xml" => false,
#     "certificate.pfx" => "" # implies it is generaterd. An empty source can be skipped from printing
# )


# function print_overrides(project_dir)

#     msix = MSIX(project_dir)

#     default_path = joinpath(dirname(@__DIR__), "recipes")

#     # SVG takes precedance

#     icon_path = get_path([joinpath(project_dir, "meta"), joinpath(dirname(@__DIR__), "recipes")], ["icon.svg", "icon.png"])

#     if issubpath(icon_path, default_path)
#         println("icon.svg => true")
#         println("icon.png => true")
#     else
#         if basename(icon_path) == "icon.svg"
#             println("icon.svg => false")
#             println("icon.png => true")
#         else
#             println("icon.svg => true")
#             println("icon.png => false")
#         end
#     end

#     println("msix/")

#     msix_dict = (
#         "Assets" => msix.icon,
#         "AppxManifest.xml" => msix.appxmanifest,
#         "resources.pri" => msix.resources_pri,
#         "MSIXAppInstallerData.xml" => msix.msixinstallerdata,
#         "certificate.pfx" => msix.pfx_cert
#     )

#     (key, value) = msix_dict[1]

#     sb = issubpath(value, default_path)

#     if isgenerated_asset(value)
#         source = basename(value)
#         println("  $key => $sb    [source = $source]")
#     else        
#         println("  $key => $sb")
#     end

#     for (key, value) in msix_dict[2:end]
#         sb = issubpath(value, default_path)
#         println("  $key => $sb")
#     end

# end


# function get_varios_preferences(ARGS; project_dir, io::IO = stdout)

#     config, preference_overrides = parse_build_args(ARGS)
#     extended_preferences = get_extended_preferences(project_dir; preference_overrides)

#     final_flat    = ArgTools.flatten_schema(extended_preferences["AppBundler"])
#     defaults_flat = ArgTools.flatten_schema(get_preferences_schema())

#     # Preferences given directly, before dynamic defaults are evaluated
#     project_preferences = Resources.get_project_preferences(project_dir)
#     project_preferences = get(project_preferences, "AppBundler", project_preferences)

#     flat_keys(d) = Set(string(k) for k in keys(ArgTools.flatten_schema(d)))
#     explicit_keys = flat_keys(preference_overrides) ∪ flat_keys(project_preferences)

#     explicit, inferred, unchanged = String[], String[], String[]

#     for key in keys(final_flat)
#         if string(key) in explicit_keys
#             push!(explicit, key)
#         elseif !haskey(defaults_flat, key) || !isequal(final_flat[key], defaults_flat[key])
#             push!(inferred, key)
#         else
#             push!(unchanged, key)
#         end
#     end

#     sort!(explicit); sort!(inferred); sort!(unchanged)

#     width = maximum(length, keys(final_flat); init = 0)

#     function print_entry(key, marker; color = :normal, bold = false)
#         line = string(marker, rpad(key, width), " => ", repr(final_flat[key]))
#         printstyled(io, line, '\n'; color, bold)
#     end

#     foreach(k -> print_entry(k, "  "; bold = true),           explicit)
#     foreach(k -> print_entry(k, "* "; bold = true),           inferred)
#     foreach(k -> print_entry(k, "  "; color = :light_black),  unchanged)

#     return final_flat
# end


# function get_varios_preferences(ARGS; project_dir, io::IO = stdout)

#     config, preference_overrides = parse_build_args(ARGS)
#     extended_preferences = get_extended_preferences(project_dir; preference_overrides)

#     # This covers prefernces that have been evalauteated without dynamic dedaults
#     preference_overrides
#     Resources.get_project_preferences(project_dir)

#     final_flat    = ArgTools.flatten_schema(extended_preferences["AppBundler"])
#     defaults_flat = ArgTools.flatten_schema(get_preferences_schema())

#     overridden = String[]   # in schema, value changed
#     inferred   = String[]   # absent from schema
#     unchanged  = String[]   # in schema, value equals default

#     for key in keys(final_flat)
#         if !haskey(defaults_flat, key)
#             push!(inferred, key)
#         elseif !isequal(final_flat[key], defaults_flat[key])
#             push!(overridden, key)
#         else
#             push!(unchanged, key)
#         end
#     end

#     sort!(overridden); sort!(inferred); sort!(unchanged)

#     width = maximum(length, keys(final_flat); init = 0)

#     function print_entry(key, marker, color)
#         line = string(marker, rpad(key, width), " => ", repr(final_flat[key]))
#         printstyled(io, line, '\n'; color)
#     end

#     for key in overridden
#         print_entry(key, "  ", :white)
#     end
#     for key in inferred
#         print_entry(key, "* ", :white)
#     end
#     for key in unchanged
#         print_entry(key, "  ", :light_black)
#     end

#     return final_flat
# end



# function get_varios_preferences(ARGS; project_dir)

#     config, preference_overrides = parse_build_args(ARGS)

#     extended_preferences = get_extended_preferences(project_dir; preference_overrides) 




#     preferences_final = extended_preferences["AppBundler"]


#     proferences_orig = get_preferences_schema()

    
#     # First shall come the keys that are present in the preferences orig in the overrides
#     # Then the keys that are absent and hence are infered
#     preferences_final_flat = ArgTools.flatten_schema(preferences_final)
    

    

#     ArgTools.flatten_schema(proferences_orig)
# end





# function main_status(ARGS; sources_dir)

#     config, preference_overrides = parse_build_args(ARGS)
#     extended_preferences = get_extended_preferences(sources_dir; preference_overrides) 
#     preferences = extended_preferences["AppBundler"]

#     # There are generated preferences
#     # Then there are overrides that can be sourced locally from prefrerence_overrides and localPreferences.toml
#     # AppBundler/preferences.toml is defaults.
    

# end
