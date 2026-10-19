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
