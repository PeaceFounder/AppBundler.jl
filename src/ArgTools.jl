"""
    ArgTools

Command-line argument handling, in two halves the caller invokes separately:

    options, defines = parse_options(ARGS)      # argv -> option => value pairs
    prefs = coerce(defines, schema)             # key => text -> key => typed value

Pairing needs no schema — one shell word is one value — so a caller can read its
options, decide which preference set applies, and coerce afterwards.

The schema is flat: dotted keys mapped to a spec, which is either a type
(`Bool`, `Int`, `String`, `Vector{String}`, …) or a tuple of allowed values:

    Dict(
        "compress"        => Bool,
        "juliaimg.sysimg" => Vector{String},
        "dmg.backend"     => ("xorriso", "hfsplus"),
    )
"""
module ArgTools

export parse_options, coerce, CoercionError

"""An option or preference and its value; `nothing` for flags, markers, bare
tokens and bare `-D` keys."""
const Arg = Pair{String, Union{String, Nothing}}


############################################################################
### Parsing: argv -> option => value pairs
############################################################################

"""
    splitpair(s) -> (key, value)

Split `s` at its first `=`. Later `=` characters belong to the value, which is
`nothing` when there is no `=` at all.
"""
function splitpair(s::AbstractString)
    j = findfirst('=', s)
    j === nothing && return SubString(s, 1), nothing
    return SubString(s, 1, prevind(s, j)), SubString(s, nextind(s, j))
end

"""Remove one layer of matching outer quotes, if the shell left any behind."""
function unquote(s::AbstractString)
    length(s) >= 2 || return s
    q = first(s)
    ((q == '"' || q == '\'') && last(s) == q) || return s
    return chop(s, head = 1, tail = 1)
end

"""Whether `token` introduces an option: a `--` or `-D` prefix, or a short alias,
whole or as the part before its first `=`."""
isoption(token, short_options) =
    startswith(token, "--") || startswith(token, "-D") ||
    haskey(short_options, first(splitpair(token)))

"""
    normalize_args(tokens; short_options) -> Vector{Arg}

Turn tokens into `option => value` pairs. Attached and detached forms are
equivalent, and only the first `=` separates option from value:

    --password=foo=bar   ⇒  "--password" => "foo=bar"
    --password foo=bar   ⇒  "--password" => "foo=bar"
    -Dbundler=juliaimg   ⇒  "-D"         => "bundler=juliaimg"
    -D bundler=juliaimg  ⇒  "-D"         => "bundler=juliaimg"
    --selfsign           ⇒  "--selfsign" => nothing
    -p=hunter2           ⇒  "--password" => "hunter2"
    -p hunter2           ⇒  "--password" => "hunter2"
    -h                   ⇒  "--help"     => nothing

An option takes the following token as its value unless that token is itself an
option. Tokens appearing where no option is open are emitted as
`token => nothing`. Values have one matching pair of outer quotes removed. The
`-D` payload is left untouched — `unquote` runs later, per list element, during
coercion.

This function pairs tokens and nothing else: it takes each one as given, so a
value keeps its brackets, commas and quotes, and never reaches across a shell
split. It needs no schema — one shell word is one value, whatever that value
will later turn out to mean.

Which tokens count as options is asymmetric, and it constrains what a detached
value can be. Any token starting with `--` or `-D` is an option, so a value
beginning with either can never be adopted: `--target-name --weird` yields two
valueless options rather than a name. Short aliases are matched exactly instead
— as a whole token, or as the part before the first `=` — so `-p` and
`-p=hunter2` are options while `-phunter2` and `-secret` remain values. An alias
is replaced by the option it names and then treated exactly like it, adopted
value included, so a short flag is only valueless when its long form is. The
attached form bypasses this check entirely and is the escape hatch for a value
that looks like an option — write `--target-name=--weird` or `-p=-h`. A value
holding spaces is the shell's business, not this function's: quote it, and
`-Dsysimg="[a, --selfsign]"` arrives as one token and one list.
"""
function normalize_args(tokens; short_options = Dict{String, String}())
    tokens = map(String, tokens)
    out = Arg[]

    i = 1
    while i <= length(tokens)
        token = tokens[i]
        i += 1

        if token == "--" || !isoption(token, short_options)
            push!(out, token => nothing)             # marker, positional, or a stray value
            continue
        end

        if startswith(token, "-D")
            option = "-D"
            payload = SubString(token, 3)            # "" for a bare -D
            value = isempty(payload) ? nothing : String(payload)
        else
            key, raw = splitpair(token)
            option = String(get(short_options, key, key))   # an alias stands in for its long form
            value = raw === nothing ? nothing : String(raw)
        end

        # Detached form: adopt the next token unless it is another option.
        if value === nothing && i <= length(tokens) && !isoption(tokens[i], short_options)
            value = tokens[i]
            i += 1
        end

        if option == "-D" || value === nothing
            push!(out, option => value)              # -D payload stays raw
        else
            push!(out, option => String(unquote(value)))
        end
    end

    return out
end

"""
    parse_options(raw_args; short_options) -> (options, defines)

Pair `raw_args` into `option => value`, and the `-D` payloads into
`key => value` of their own: `-Dsysimg=[QMLApp]` becomes
`"sysimg" => "[QMLApp]"`, and a bare `-Dselfsign` becomes
`"selfsign" => nothing`. Both halves are `Arg` vectors; the difference is that
the second names preferences rather than options.

The value stays the text the shell delivered: one shell word is one value,
whatever that value will turn out to mean. Reading `"[QMLApp]"` as the
one-element list `["QMLApp"]` is coercion, and coercion needs the schema.

This is the half of parsing a caller can do first — read the subcommand, spot
`--help`, hand the rest on — and only then choose a schema and call
[`coerce`](@ref) on `defines`.

    options, defines = parse_options(ARGS; short_options = Dict("-h" => "--help"))
    prefs = coerce(defines, schema_for(options))
"""
function parse_options(raw_args; short_options = Dict{String, String}())
    options = Arg[]
    defines = Arg[]

    for (key, value) in normalize_args(raw_args; short_options)
        if key != "-D"
            push!(options, key => value)
            continue
        end

        value === nothing && error("-D expects key=value, e.g. -Dbundler=juliaimg")
        name, raw = splitpair(value)
        push!(defines, String(strip(name)) => (raw === nothing ? nothing : String(raw)))
    end

    return options, defines
end


############################################################################
### Coercion: key => text -> key => typed value, against a flat schema
############################################################################

"""
    scan(v) -> (breaks, open_quote, depth)

Walk a value once, tracking quoting and bracket nesting. `breaks` holds the
indices of the top-level commas — the element separators — while `open_quote`
and `depth` describe the state left at the end: a quote still open or a positive
depth means the value is unterminated.

A quote only opens at the start of an element (after `[`, `{`, `,`, or leading
whitespace), so an apostrophe inside a word is an ordinary character.
"""
function scan(v::AbstractString)
    breaks = Int[]
    open_quote = nothing
    depth = 0
    at_element_start = true
    for (i, c) in pairs(v)
        if open_quote !== nothing
            if c == open_quote
                open_quote = nothing
                at_element_start = false
            end
        elseif at_element_start && (c == '"' || c == '\'')
            open_quote = c
        elseif c == '[' || c == '{'
            depth += 1
            at_element_start = true
        elseif c == ']' || c == '}'
            depth -= 1
            at_element_start = false
        elseif c == ','
            depth == 0 && push!(breaks, i)
            at_element_start = true
        elseif !isspace(c)
            at_element_start = false
        end
    end
    return breaks, open_quote, depth
end

"""
    split_elements(body) -> (parts, open_quote, depth)

Split a list body on its top-level commas, and hand back the state the scan
ended in. Commas inside quotes or nested brackets belong to an element. A quote
still open or a nonzero `depth` means the body is malformed; the caller decides
what to say about it.
"""
function split_elements(body::AbstractString)
    breaks, open_quote, depth = scan(body)
    parts = String[]
    start = firstindex(body)
    for i in breaks
        push!(parts, body[start:prevind(body, i)])
        start = nextind(body, i)
    end
    push!(parts, body[start:end])
    return parts, open_quote, depth
end

"""
    isquoted(s) -> Bool

Whether `s` is one quoted span and nothing else: a quote at the first character
whose first match is the last character. `"a,b"` qualifies; `"a","b"` does not,
its closing quote falling in the middle. This is the question `unquote` should
be asking but cannot, since it only compares the two end characters.
"""
function isquoted(s::AbstractString)
    length(s) >= 2 || return false
    q = first(s)
    (q == '"' || q == '\'') || return false
    return findnext(q, s, nextind(s, firstindex(s))) == lastindex(s)
end

"""Whether `s` is written as an explicit bracketed list."""
islist(s::AbstractString) = startswith(s, '[') && endswith(s, ']')

"""Trim a scalar and take one layer of quotes off it — the last step before parsing."""
unwrap(value::AbstractString) = unquote(strip(value))

"""How a schema spec is named in an error message."""
spec_name(::Type{<:AbstractString}) = "a string"
spec_name(::Type{Bool}) = "true or false"
spec_name(::Type{<:Integer}) = "an integer"
spec_name(::Type{<:AbstractFloat}) = "a number"
spec_name(::Type{<:AbstractVector}) = "a list"
spec_name(options::Tuple) = "one of " * join(("'$o'" for o in options), ", ", " or ")
spec_name(spec) = "a $spec"

"""Report an unknown preference, naming any schema key within a few edits of it."""
function unknown_key_message(key, schema)
    threshold = max(2, length(key) ÷ 4)
    near = sort!([string(k) for k in keys(schema) if edit_distance(key, k) <= threshold])
    msg = "unknown preference '$key'"
    isempty(near) || (msg *= "\n       did you mean " * join(("'$k'" for k in near), ", ", " or ") * "?")
    return msg
end

"""Levenshtein distance between `a` and `b`, carried on two rolling rows."""
function edit_distance(a, b)
    prev = collect(0:length(b))
    curr = similar(prev)
    for (i, ca) in enumerate(a)
        curr[1] = i
        for (j, cb) in enumerate(b)
            curr[j+1] = min(prev[j+1] + 1, curr[j] + 1, prev[j] + (ca != cb))
        end
        prev, curr = curr, prev
    end
    return prev[end]
end

"""A command-line value that does not fit its spec; the caller adds whose value it was."""
struct CoercionError <: Exception
    msg::String
end

Base.showerror(io::IO, err::CoercionError) = print(io, err.msg)

const LIST_HINT = """
    Write the list without spaces, or bracket it so its end is explicit:
        -Dsysimg=a,b        or        -Dsysimg=[a, b]
    """



"""
    coerce(defines, schema) -> Vector{Pair{String, Any}}

Coerce the `key => value` pairs from [`parse_options`](@ref) against a flat
`schema` of dotted keys, keeping their order. An unknown key is an error with
near misses suggested, and a bad value is an error naming its key.

A key given more than once keeps its last value. A key the schema declares a
list accumulates instead: a bare value appends to the list, while a bracketed
one resets it to that value. The key keeps the position of its first
occurrence.

    -Dsysimg=a -Dsysimg=b           # sysimg = ["a", "b"]
    -Dsysimg=a -Dsysimg=[b, c]      # sysimg = ["b", "c"]
    -Dsysimg=[a] -Dsysimg=b         # sysimg = ["a", "b"]
    -Dsysimg=a -Dsysimg=[]          # sysimg = []

    options, defines = parse_options(ARGS)
    prefs = coerce(defines, schema)
"""
function coerce(defines::AbstractVector{<:Pair}, schema::AbstractDict)
    typed = Pair{String, Any}[]
    position = Dict{String, Int}()          # key => index in `typed`

    for (key, raw) in defines
        key = String(key)
        haskey(schema, key) || error(unknown_key_message(key, schema))
        spec = schema[key]

        value = try
            #@show key, raw, spec
            if raw isa AbstractString
                coerce(strip(raw), spec)
            else
                coerce(raw, spec)
            end
                #coerce(raw === nothing ? nothing : strip(raw), spec)

        catch err
            err isa CoercionError || rethrow()
            error("preference '$key' $(err.msg)")
        end

        i = get(position, key, 0)
        if i == 0                                        # first occurrence
            push!(typed, key => value)
            position[key] = length(typed)
        elseif islisttype(spec) && !resets_list(raw)     # bare value: append
            typed[i] = key => vcat(last(typed[i]), value)
        else                                             # scalar, or bracketed list: replace
            typed[i] = key => value
        end
    end
    return typed
end

"""Whether a schema spec describes a list-valued preference."""
islisttype(spec) = spec isa Type && spec <: AbstractVector

"""
Whether the raw text of a list preference is written as an explicit list, which
resets the preference instead of appending to it. A wholly quoted list counts,
as it does in list coercion.
"""
function resets_list(raw)
    raw === nothing && return false
    s = strip(raw)
    isquoted(s) && (s = strip(unquote(s)))
    return islist(s)
end



"""
    coerce(value, spec) -> Any

Interpret the command-line text `value` according to a schema `spec`: a type, or
a tuple of allowed values. The string is never inspected to guess a type; the
schema decides. Throws [`CoercionError`](@ref) when the value does not fit.

`nothing` — a bare `-Dkey` — stands for `true` and is only allowed where the spec
is `Bool`.

Quotes come off at the leaf, once. A list therefore sees its payload as written:
a wholly quoted one is a single element, and quotes inside a bracketed one
protect the commas they enclose. Elements are coerced to `eltype(spec)`, so
`Vector{Int}` does not quietly become a list of strings.

A blank element is an error — `[a,,b]` and `[,a]` are malformed rather than
carriers of an empty string, which is written `["", a]`. The one exception is a
single trailing comma inside brackets, which is conventional and ignored.

A bracket or quote left open is an error too. One shell word is one value, so
`-Dsysimg=[a, b]` must be quoted or written without the space; there is no pass
that reaches forward across argv to close it.
"""
function coerce(value::AbstractString, ::Type{T}) where {T <: AbstractVector}
    E = eltype(T)
    body = strip(value)
    bracketed = false

    if isquoted(body)
        inner = strip(unquote(body))
        isempty(inner) && return E[]
        islist(inner) || return E[coerce(inner, E)]
        body = inner
    end

    if islist(body)
        bracketed = true
        body = strip(chop(body, head = 1, tail = 1))
    end
    isempty(body) && return E[]

    parts, open_quote, depth = split_elements(body)

    depth < 0 && throw(CoercionError("has an unexpected ']' or '}' in '$value'\n" * LIST_HINT))
    (open_quote === nothing && depth == 0) ||
        throw(CoercionError("has an unterminated value '$value'\nMissing a closing ']' or '\"'.\n" * LIST_HINT))

    bracketed && isempty(strip(last(parts))) && pop!(parts)
    any(p -> isempty(strip(p)), parts) &&
        throw(CoercionError("has a blank element in '$value'\n" * LIST_HINT))

    return E[coerce(p, E) for p in parts]
end

coerce(value::AbstractString, ::Type{<:AbstractString}) = String(unwrap(value))

coerce(value::AbstractString, ::Type{Any}) = String(unwrap(value))

function coerce(value::AbstractString, ::Type{Bool})
    v = unwrap(value)
    v in ("true", "false") || throw(CoercionError("expects true or false, got '$v'"))
    return v == "true"
end

function coerce(value::AbstractString, ::Type{T}) where {T <: Integer}
    v = unwrap(value)
    n = tryparse(T, v)
    n === nothing && throw(CoercionError("expects an integer, got '$v'"))
    return n
end

function coerce(value::AbstractString, ::Type{T}) where {T <: AbstractFloat}
    v = unwrap(value)
    x = tryparse(T, v)
    x === nothing && throw(CoercionError("expects a number, got '$v'"))
    return x
end

# Allowed values: the text must equal one of the options as written; the option itself is returned
function coerce(value::AbstractString, options::Tuple)
    v = unwrap(value)
    i = findfirst(o -> string(o) == v, options)
    i === nothing && throw(CoercionError("expects $(spec_name(options)), got '$v'"))
    return options[i]
end

coerce(::AbstractString, spec) =
    throw(CoercionError("has a schema entry $spec, which cannot be set from the command line"))

# A bare `-Dkey` stands for `true`, and only for booleans
coerce(::Nothing, ::Type{Bool}) = true

coerce(::Nothing, spec) =
    throw(CoercionError("expects $(spec_name(spec)); bare keys are only allowed for booleans"))

coerce(value::T, ::Type{T}) where T = value

end
