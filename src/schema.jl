
const LOCAL_PREFERENCES_SCHEMA = Dict{String, Any}(
    "app_name" => String,
    "app_display_name" => String,
    "app_exe" => String,
    "app_summary" => String,
    "app_description" => String,
    "bundle_identifier" => String,
    "module_name" => String,
    "publisher_name" => String,
    "version" => String,
    "build_number" => Int,

    "bundler" => ("juliaimg", "juliac"),
    "windowed" => Bool,
    "compress" => Bool,
    "selfsign" => Bool,
    "skipsign" => Bool,
    "overwrite_target" => Bool,
    "verbose" => Bool,

    "juliaimg.precompile" => Bool,
    "juliaimg.incremental" => Bool,
    "juliaimg.mainless" => Bool,
    "juliaimg.selective_assets" => Bool,
    "juliaimg.sysimg" => Vector{String},

    "juliac.trim" => Bool,

    "msix.command" => Vector{String},
    "msix.publisher" => String,
    "msix.store_icon_plate" => String,
    "msix.path_length_threshold" => Int,
    "msix.skip_long_paths" => Bool,
    "msix.skip_symlinks" => Bool,
    "msix.skip_unicode_paths" => Bool,
    "msix.bootstrapper" => Bool,
    "msix.bootstrapper_windowed" => Bool,

    "dmg.command" => Vector{String},
    "dmg.backend" => ("xorriso", "hfsplus"),
    "dmg.compression" => ("lzma", "bzip2", "zlib", "lzfse"),
    "dmg.hardened_runtime" => Bool,
    "dmg.sandboxed_runtime" => Bool,
    "dmg.shallow_signing" => Bool,
    "dmg.xorriso.hfsplus" => Bool,
    "dmg.hfsplus.free_space" => Int,

    "snap.command" => Vector{String},

    "appimage.command" => Vector{String},
    "appimage.compression" => ("zstd", "gzip", "xz"),
)


# ── Checking ──────────────────────────────────────────────────────────────────

isallowed(spec::Type, value) = value isa spec
isallowed(options::Tuple, value) = value in options
isallowed(::Type{Vector{String}}, value) = value isa AbstractVector && all(x -> x isa AbstractString, value)

describe(spec::Type) = "a value of type $spec"
describe(::Type{Vector{String}}) = "a list of strings"
describe(options::Tuple) = "one of " * join(repr.(options), ", ")

# ── Coercion of single values ─────────────────────────────────────────────────

# Values that already have the right type (e.g. read from TOML) pass through unchanged
function coerce(value, spec)
    isallowed(spec, value) || throw(ArgumentError("expected $(describe(spec)), got $(repr(value))"))
    return value
end

coerce(value::AbstractString, ::Type{String}) = String(value)

# A bare `-Dflag` without a value switches a boolean on
coerce(::Nothing, ::Type{Bool}) = true

function coerce(value::AbstractString, ::Type{Bool})
    parsed = tryparse(Bool, lowercase(strip(value)))
    isnothing(parsed) && throw(ArgumentError("expected true or false, got $(repr(value))"))
    return parsed
end

function coerce(value::AbstractString, ::Type{Int})
    parsed = tryparse(Int, strip(value))
    isnothing(parsed) && throw(ArgumentError("expected an integer, got $(repr(value))"))
    return parsed
end



# # A double-quoted item (with escapes), a single-quoted literal, or a bare item up to the next comma
# const LIST_ITEM = r"\"((?:[^\"\\]|\\.)*)\"|'([^']*)'|([^,]+)"

# # Accepts `["a", "b"]`, `['a', 'b']` or a plain comma-separated list `a, b`
# function coerce(value::AbstractString, ::Type{Vector{String}})
#     s = strip(value)
#     if startswith(s, "[")
#         endswith(s, "]") || throw(ArgumentError("unterminated list, got $(repr(value))"))
#         s = chop(s; head = 1, tail = 1)
#     end

#     items = String[]
#     for m in eachmatch(LIST_ITEM, s)
#         if !isnothing(m[1])
#             push!(items, unescape_string(m[1]))
#         elseif !isnothing(m[2])
#             push!(items, m[2])
#         else
#             item = strip(m[3])
#             isempty(item) || push!(items, item)
#         end
#     end
#     return items
# end




const LIST_HINT = """
    Write the list without spaces, or bracket it so its end is explicit:
        -Dsysimg=a,b        or        -Dsysimg=[a, b]
    """

"""
    coerce(value, T, key) -> Any

Interpret `value` as a `T`, the type of the preference's default. The string is
never inspected to guess a type; the schema decides.

Quotes come off at the leaf, once. A list therefore sees its payload as written:
a wholly quoted one is a single element, and quotes inside a bracketed one
protect the commas they enclose. Elements are coerced to `eltype(T)`, so an
empty default still says what its elements are and `Int[]` does not quietly
become a list of strings; an untyped `[]` reads its elements as strings.

A blank element is an error — `[a,,b]` and `[,a]` are malformed rather than
carriers of an empty string, which is written `["", a]`. The one exception is a
single trailing comma inside brackets, which is conventional and ignored.

A bracket or quote left open is an error too. One shell word is one value, so
`-Dsysimg=[a, b]` must be quoted or written without the space; there is no pass
that reaches forward across argv to close it.
"""
function coerce(value::AbstractString, ::Type{T}, key) where {T <: AbstractVector}
    E = eltype(T)
    body = strip(value)
    bracketed = false

    if isquoted(body)
        inner = strip(unquote(body))
        isempty(inner) && return E[]
        islist(inner) || return E[coerce(inner, E, key)]
        body = inner
    end

    if islist(body)
        bracketed = true
        body = strip(chop(body, head = 1, tail = 1))
    end
    isempty(body) && return E[]

    parts, open_quote, depth = split_elements(body)

    depth < 0 && error("""
        Unexpected ']' or '}' in value of preference '$key': '$value'
        """ * LIST_HINT)
    (open_quote === nothing && depth == 0) || error("""
        Unterminated value for preference '$key': '$value'
        Missing a closing ']' or '"'.
        """ * LIST_HINT)

    bracketed && isempty(strip(last(parts))) && pop!(parts)
    any(p -> isempty(strip(p)), parts) &&
        error("""
            Blank element in value of preference '$key': '$value'
            """ * LIST_HINT)

    return E[coerce(p, E, key) for p in parts]
end

coerce(value::AbstractString, ::Type{<:AbstractString}, key) = String(unwrap(value))

coerce(value::AbstractString, ::Type{Any}, key) = String(unwrap(value))

function coerce(value::AbstractString, ::Type{Bool}, key)
    v = unwrap(value)
    v in ("true", "false") ||
        error("preference '$key' expects true or false, got '$v'")
    return v == "true"
end

function coerce(value::AbstractString, ::Type{T}, key) where {T <: Integer}
    v = unwrap(value)
    n = tryparse(T, v)
    n === nothing && error("preference '$key' expects an integer, got '$v'")
    return n
end

function coerce(value::AbstractString, ::Type{T}, key) where {T <: AbstractFloat}
    v = unwrap(value)
    x = tryparse(T, v)
    x === nothing && error("preference '$key' expects a number, got '$v'")
    return x
end

coerce(::AbstractString, ::Type{T}, key) where {T} =
    error("preference '$key' has a default of type $T, which cannot be set from the command line")





# # Accepts TOML array syntax `["a", "b"]` or a plain comma-separated list `a,b`
# function coerce(value::AbstractString, T::Type{Vector{String}})
#     s = strip(value)
#     items = if startswith(s, "[")
#         try
#             TOML.parse("x = " * s)["x"]
#         catch
#             throw(ArgumentError("expected a list such as [\"a\", \"b\"], got $(repr(value))"))
#         end
#     else
#         isempty(s) ? String[] : strip.(split(s, ','))
#     end
#     return coerce(items, T)
# end

function coerce(value::AbstractVector, ::Type{Vector{String}})
    isallowed(Vector{String}, value) || throw(ArgumentError("expected a list of strings, got $(repr(value))"))
    return String[x for x in value]
end

function coerce(value::AbstractString, options::Tuple)
    value in options || throw(ArgumentError("expected $(describe(options)), got $(repr(value))"))
    return String(value)
end

# ── Coercion of command-line defines ──────────────────────────────────────────

"""
    coerce(defines, schema = LOCAL_PREFERENCES_SCHEMA) -> Vector{Pair{String,Any}}

Convert `"dotted.key" => raw_value` pairs from the command line into the types the
schema declares. Errors name the offending key.
"""
function coerce(defines::AbstractVector{<:Pair}, schema::AbstractDict = LOCAL_PREFERENCES_SCHEMA)
    typed = Pair{String,Any}[]
    for (key, value) in defines
        key = string(key)
        haskey(schema, key) || error("Unknown preference `$key`")
        coerced = try
            coerce(value, schema[key])
        catch err
            err isa ArgumentError || rethrow()
            error("Preference `$key`: $(err.msg)")
        end
        push!(typed, key => coerced)
    end
    return typed
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

# ── Validation of a full preferences dictionary ───────────────────────────────

"""
    validate(preferences, schema = LOCAL_PREFERENCES_SCHEMA)

Check every (flattened) key of `preferences` against the schema. Reports all unknown keys and
invalid values together; returns `preferences` unchanged when everything is valid.
"""
function validate(preferences::AbstractDict, schema::AbstractDict = LOCAL_PREFERENCES_SCHEMA)
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

