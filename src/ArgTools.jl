"""
    ArgTools

Command-line argument handling, in two halves the caller invokes separately:

    options, defines = parse_options(ARGS)      # argv -> option => value pairs
    prefs = parse_preferences(defines, schema)  # key => text -> key => typed value

Pairing needs no schema — one shell word is one value — so a caller can read its
options, decide which preference set applies, and coerce afterwards.
"""
module ArgTools

export parse_options, parse_preferences

"""An option or preference and its value; `nothing` for flags, markers, bare
tokens and bare `-D` keys."""
const Arg = Pair{String, Union{String, Nothing}}


### Scanning

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
what to say about it, since only it knows whose value this is.
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


### Normalisation

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
type coercion.

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


### Quoting

"""Remove one layer of matching outer quotes, if the shell left any behind."""
function unquote(s::AbstractString)
    length(s) >= 2 || return s
    q = first(s)
    ((q == '"' || q == '\'') && last(s) == q) || return s
    return chop(s, head = 1, tail = 1)
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


### Coercion against the schema

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

"""Trim a scalar and take one layer of quotes off it — the last step before parsing."""
unwrap(value::AbstractString) = unquote(strip(value))

"""How the type of a default is named in an error message."""
type_name(::AbstractString) = "a string"
type_name(::Bool) = "true or false"
type_name(::Integer) = "an integer"
type_name(::AbstractFloat) = "a number"
type_name(::AbstractVector) = "a list"
type_name(x) = "a $(typeof(x))"

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


### Entry points

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
[`parse_preferences`](@ref) on `defines`.

    options, defines = parse_options(ARGS; short_options = Dict("-h" => "--help"))
    prefs = parse_preferences(defines, schema_for(options))
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

"""
    parse_preferences(defines, schema; on_repeat) -> Dict{String, Any}

Coerce the `key => value` pairs from [`parse_options`](@ref) against the schema.
An unknown key is an error with near misses suggested; a known one has its value
read as the type of its default. A `nothing` value — a bare `-Dkey` — stands for
`true` and is only allowed where that default is a `Bool`.

A repeated key accumulates where its default is a list — `-Dsysimg=a -Dsysimg=b`
is the two-element form that needs no whitespace repair — and an empty payload
clears what came before, so `-Dsysimg=` starts the list over. A repeated scalar
takes its last value, the way a repeated flag does.

`on_repeat = :error` makes a second mention of a key an error instead, lists
included: every preference must then be written exactly once. That suits a build
where a wrong preference is expensive, since it changes the artifact silently;
it does not suit a wrapper script that prepends defaults for the user to
override.
"""
function parse_preferences(defines, schema::AbstractDict; on_repeat::Symbol = :last)
    on_repeat in (:last, :error) ||
        error("on_repeat must be :last or :error, got :$on_repeat")

    overrides = Dict{String, Any}()

    for (key, raw) in defines
        haskey(schema, key) || error(unknown_key_message(key, schema))
        default = schema[key]

        if raw === nothing
            default isa Bool || error("preference '$key' expects $(type_name(default)); " *
                                      "bare keys are only allowed for booleans. Use -D$key=<value>.")
            value = true
        else
            value = coerce(strip(raw), typeof(default), key)
        end

        if !haskey(overrides, key)
            overrides[key] = value
        elseif on_repeat === :error
            error("preference '$key' is set more than once, to '$(overrides[key])' and then " *
                  "'$value'. Set it once.")
        elseif !(default isa AbstractVector)
            overrides[key] = value                   # a later scalar replaces
        elseif isempty(value)
            overrides[key] = value                   # an empty payload clears the list
        else
            append!(overrides[key], value)
        end
    end

    return overrides
end

end
