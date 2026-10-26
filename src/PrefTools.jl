module PrefTools

import TOML


export apply_overrides!, validate


# This is a bit of a hack but shall work fine
function get_project_preferences(project)

    push!(Base.LOAD_PATH, pkgdir(@__MODULE__))
    pushfirst!(Base.LOAD_PATH, project)
    try
        return Base.get_preferences()
    finally
        popfirst!(Base.LOAD_PATH)
        pop!(Base.LOAD_PATH)
    end
end


"""
    nest_keys(flat) -> Dict{String, Any}

Inverse of [`flatten_schema`](@ref): turn `"juliaimg.sysimg" => ["GtkApp"]` into
`"juliaimg" => Dict("sysimg" => ["GtkApp"])`.
"""
function nest_keys(flat)
    nested = Dict{String, Any}()
    for (key, value) in flat
        parts = split(key, '.')
        node = nested
        for part in parts[1:end-1]
            node = get!(Dict{String, Any}, node, String(part))
        end
        node[String(parts[end])] = value
    end
    return nested
end

"""
    flatten_schema(schema) -> Dict{String, Any}

Map every value in a nested schema to its dotted path, `"juliaimg.sysimg" => []`.
Tables themselves get no entry.
"""
function flatten_schema(schema::AbstractDict, prefix::AbstractString = "")
    flat = Dict{String, Any}()
    for (key, value) in schema
        path = isempty(prefix) ? key : "$prefix.$key"
        if value isa AbstractDict
            merge!(flat, flatten_schema(value, path))
        else
            flat[path] = value
        end
    end
    return flat
end


function apply_overrides!(preferences, overrides)

    preference_overrides = nest_keys(overrides)

    custom_merge(a::Dict, b::Dict) = merge(a, b)
    custom_merge(a::T, b::T) where T = b
    custom_merge(a, b) = error("Incompatable types")

    mergewith!(custom_merge, preferences, preference_overrides)
    
    return preferences
end

# ── Validation of a full preferences dictionary ───────────────────────────────

# A value fits a type spec when it is an instance of it
isallowed(spec::Type, value) = value isa spec

# Allowed values: the value must be one of the listed options
isallowed(options::Tuple, value) = value in options

# TOML may parse a list as `Vector{Any}` (always so for `[]`), so check the elements instead
isallowed(::Type{Vector{String}}, value) =
    value isa AbstractVector && all(x -> x isa AbstractString, value)

describe(spec::Type) = "a value of type $spec"
describe(::Type{Vector{String}}) = "a list of strings"
describe(options::Tuple) = "one of " * join(repr.(options), ", ")


"""
    validate(preferences, schema = LOCAL_PREFERENCES_SCHEMA)

Check every (flattened) key of `preferences` against the schema. Reports all unknown keys and
invalid values together; returns `preferences` unchanged when everything is valid.
"""
function validate(preferences::AbstractDict, schema::AbstractDict)
    problems = String[]
    for (key, value) in flatten_schema(preferences)
        key = string(key)
        if !haskey(schema, key)
            push!(problems, "unknown preference `$key`")
        elseif !isallowed(schema[key], value)
            push!(problems, "`$key` must be $(describe(schema[key])), got $(repr(value))")
        end
    end
    isempty(problems) || error("Invalid preferences:\n  " * join(sort!(problems), "\n  "))
    return preferences
end



toml_line(key, value) = key * chopprefix(rstrip(sprint(TOML.print, Dict("x" => value))), "x")

# Insert `line` at the end of the `[table]` block; `nothing` if the file has no such header
function insert_line(text, table, line)
    block = Regex("^[ \\t]*\\[" * replace(table, "." => "\\.") * "\\][^\\n]*(?:\\n(?![ \\t]*\\[)[^\\n]*)*", "m")
    occursin(block, text) || return nothing
    return replace(text, block => function (b)
        body = rstrip(b)
        body * "\n" * match(r"^[ \t]*", b).match * line * chopprefix(b, body)
    end; count = 1)
end

"""
    inline_preferences(destination, defines; section = "AppBundler", schema = LOCAL_PREFERENCES_SCHEMA)

Add `defines`, the `key => text` pairs from `ArgTools.parse_options`, to `[section]` of the TOML
file at `destination`. Values are coerced against `schema`, and each new line is inserted into the
table block it belongs to, leaving the rest of the file untouched. Errors if any key is already set.
"""
#function inline_preferences(destination, defines; force = true, section = "AppBundler", schema = LOCAL_PREFERENCES_SCHEMA)
#function inline_preferences(destination, defines; force = true, section = "AppBundler", schema = Dict{String, Any}())
function inline_preferences(destination, defines; force = true, section = "AppBundler")
    #defines = ArgTools.coerce(defines, schema)

    text = isfile(destination) ? read(destination, String) : ""
    current = flatten_schema(get(TOML.parse(text), section, Dict{String,Any}()))

    already = sort!([key for (key, _) in defines if haskey(current, key)])
    isempty(already) || error("$destination already sets " * join(already, ", "))

    for (key, value) in defines
        parts = split(key, '.')
        updated = nothing
        for n in length(parts)-1:-1:0          # deepest existing table header on the key's path
            table = join([section; parts[1:n]], '.')
            updated = insert_line(text, table, toml_line(join(parts[n+1:end], '.'), value))
            isnothing(updated) || break
        end
        text = something(updated,
            (isempty(strip(text)) ? "" : rstrip(text) * "\n\n") * "[$section]\n" * toml_line(key, value) * "\n")
    end

    # Safety net: the edited text must parse, and every value must read back where it was meant to land
    written = flatten_schema(get(TOML.parse(text), section, Dict{String,Any}()))
    misplaced = [key for (key, value) in defines if get(written, key, nothing) != value]
    isempty(misplaced) || error("Could not place " * join(misplaced, ", ") * " in $destination")

    write(destination, text)
    return destination
end



#flat_keys(d) = Set(string(k) for k in keys(ArgTools.flatten_schema(d)))

# function load_preferences_section(path; section = "AppBundler")
#     isfile(path) || return Dict{String,Any}()
#     return get(TOML.parsefile(path), section, Dict{String,Any}())
# end

# # Keys set in the project's LocalPreferences.toml or on the command line
# function explicit_preference_keys(project_dir, preference_overrides)
#     keys_project = isnothing(project_dir) ? Set{String}() :
#         flat_keys(load_preferences_section(joinpath(project_dir, "LocalPreferences.toml")))
#     return keys_project ∪ flat_keys(preference_overrides)
# end

# Keys absent from AppBundler's static defaults and not set explicitly
function inferred_preference_keys(final_flat, explicit_keys)
    defaults = load_preferences_section(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml"))
    return setdiff(keys(final_flat), flat_keys(defaults), explicit_keys)
end

module PreferenceStatus
    @enum T ERROR EXPLICIT INFERRED DEFAULT
end

const PreferenceEntry = @NamedTuple{key::String, value::Any, status::PreferenceStatus.T}

# Keys in the [AppBundler] section of a LocalPreferences.toml, flattened
function preference_file_keys(path)
    isfile(path) || return Set{String}()
    section = get(TOML.parsefile(path), "AppBundler", Dict{String,Any}())
    return Set(keys(flatten_schema(section)))
end

# """
#     preferences_status(project; defines = Pair{String,Any}[], schema = LOCAL_PREFERENCES_SCHEMA)

# Resolve the project's preferences the way `load_preferences` does, and classify every key:
# - `PreferenceStatus.ERROR`    : not in the schema, or a value the schema does not allow
# - `PreferenceStatus.EXPLICIT` : set in the project's LocalPreferences.toml or by `defines`
# - `PreferenceStatus.INFERRED` : not among AppBundler's static defaults and not set explicitly
# - `PreferenceStatus.DEFAULT`  : AppBundler's static default

# Unlike `load_preferences`, invalid entries are reported as `ERROR` rather than thrown, so they can
# be shown alongside everything else.
# """
# #function preferences_status(project; defines::Vector{Pair{String,Any}} = Pair{String,Any}[], schema = LOCAL_PREFERENCES_SCHEMA)
# function preferences_status(project, schema; defines::Vector{Pair{String,Any}} = Pair{String,Any}[])
#     preferences = deepcopy(get_project_preferences(project))
#     section = preferences["AppBundler"]

#     #overrides = ArgTools.coerce(defines, schema)
#     PrefTools.apply_overrides!(section, defines)
    
#     apply_defaults!(section, project)
#     final_flat = PrefTools.flatten_schema(section)

#     explicit_keys = preference_file_keys(joinpath(project, "LocalPreferences.toml")) ∪ first.(defines)
#     default_keys = preference_file_keys(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml"))
#     inferred_keys = setdiff(keys(final_flat), default_keys, explicit_keys)

#     status(k, v) = !haskey(schema, k) || !isallowed(schema[k], v) ? PreferenceStatus.ERROR    :
#                    k in explicit_keys                              ? PreferenceStatus.EXPLICIT :
#                    k in inferred_keys                              ? PreferenceStatus.INFERRED :
#                                                                      PreferenceStatus.DEFAULT

#     entries = PreferenceEntry[(key = k, value = v, status = status(k, v)) for (k, v) in final_flat]
#     return sort!(entries; by = e -> (e.status, e.key))
# end








function preferences_status(
    default_preferences::AbstractDict,
    project_preferences::AbstractDict,
    schema::AbstractDict;
    infer! = identity,
)
    #section = deepmerge(default_preferences, project_preferences)
    preferences = apply_overrides!(deepcopy(default_preferences), project_preferences)
    infer!(preferences)
    final_flat = flatten_schema(preferences)

    layers = [
        :default => flat_keys(default_preferences),
        :project => flat_keys(project_preferences),
    ]

    entries = [(; e..., error = validate(schema, e.key, e.value))
               for e in resolve_sources(final_flat, layers)]

    order = (:project, :inferred, :default)
    return sort!(entries; by = e -> (isnothing(e.error), findfirst(==(e.source), order), e.key))
end


end
