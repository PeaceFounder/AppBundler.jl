module PrefTools

import TOML

export apply_overrides!, validate, preferences_status

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
function inline_preferences(destination, defines; force = true, section = "AppBundler")

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

function preferences_status(
    default_preferences::AbstractDict,
    project_preferences::AbstractDict,
    schema::AbstractDict;
    infer! = identity,
)
    preferences = apply_overrides!(deepcopy(default_preferences), project_preferences)

    try
        infer!(preferences)
    catch
        # Keys that could not be inferred are reported as ERROR entries below
    end

    final_flat = flatten_schema(preferences)

    explicit_keys = Set(keys(flatten_schema(project_preferences)))
    default_keys  = Set(keys(flatten_schema(default_preferences)))

    function status(k, v)
        if !haskey(schema, k) || !isallowed(schema[k], v)
            return PreferenceStatus.ERROR
        elseif k in explicit_keys
            return PreferenceStatus.EXPLICIT
        elseif k in default_keys
            return PreferenceStatus.DEFAULT
        else
            return PreferenceStatus.INFERRED
        end
    end

    entries = PreferenceEntry[(key = k, value = v, status = status(k, v)) for (k, v) in final_flat]

    for key in setdiff(keys(schema), keys(final_flat))
        push!(entries, (key = key, value = nothing, status = PreferenceStatus.ERROR))
    end

    return sort!(entries; by = e -> (e.status, e.key))
end

function preferences_status(project::AbstractString, schema::AbstractDict; infer! = identity, section = "AppBundler", defines = Pair{String,Any}[])

    load(path) = isfile(path) ? get(TOML.parsefile(path), section, Dict{String,Any}()) : Dict{String,Any}()

    project_preferences = load(joinpath(project, "LocalPreferences.toml"))
    apply_overrides!(project_preferences, defines) # defines must be coerced before applied

    return preferences_status(
        load(joinpath(pkgdir(@__MODULE__), "LocalPreferences.toml")),
        project_preferences,
        schema;
        infer!
    )
end

end
