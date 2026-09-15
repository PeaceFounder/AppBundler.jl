"""
    ArgTools

Command-line argument handling: rejoin values the shell split on whitespace,
turn tokens into `option => value` pairs, and coerce `-Dkey=value` payloads
against a schema of default values.
"""
module ArgTools

export parse_args

"""An option and its value; `nothing` for flags, markers and bare tokens."""
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
    split_elements(body) -> Vector{String}

Split a list body on its top-level commas. Commas inside quotes or nested
brackets belong to an element.
"""
function split_elements(body::AbstractString)
    breaks, _, _ = scan(body)
    parts = String[]
    start = firstindex(body)
    for i in breaks
        push!(parts, body[start:prevind(body, i)])
        start = nextind(body, i)
    end
    push!(parts, body[start:end])
    return parts
end


### Healing

const LIST_HINT = """
    Write the list without spaces, or bracket it so its end is explicit:
        -Dsysimg=a,b        or        -Dsysimg=[a, b]
    """

"""
    list_payload(token, prev, schema) -> value or nothing

The value of `token`, if and only if it is a `-D` payload whose key the schema
declares a list: `-Dsysimg=...`, or `sysimg=...` following a bare `-D`. For
anything else — another option, a positional, a detached value, or a `-D` key
that is unknown or holds a scalar — the answer is `nothing` and the token is
left exactly as the shell delivered it.

This is what makes healing a completion rather than a guess. An open `[` is only
read as "more is coming" where a list was expected, and there it cannot mean
anything else.
"""
function list_payload(token, prev, schema)
    if startswith(token, "-D")
        body = SubString(token, 3)
    elseif prev == "-D"
        body = SubString(token, 1)
    else
        return nothing
    end

    key, value = splitpair(body)
    value === nothing && return nothing
    get(schema, String(strip(key)), nothing) isa AbstractVector || return nothing
    return value
end

"""
    absorb(tokens, i, prev, schema) -> (token, i)

Grow `tokens[i]` until its list value closes every quote and bracket it opened,
returning the healed token and the index of the last token consumed.
"""
function absorb(tokens, i, prev, schema)
    token = tokens[i]
    value = list_payload(token, prev, schema)
    value === nothing && return token, i

    while true
        _, open_quote, depth = scan(value)

        depth < 0 && error("""
            Unexpected ']' or '}' in value: $token
            """ * LIST_HINT)
        open_quote === nothing && depth == 0 && break

        i += 1
        i > length(tokens) && error("""
            Unterminated value: $token
            Missing a closing ']' or '"'.
            """ * LIST_HINT)
        token *= " " * tokens[i]
        value = something(list_payload(token, prev, schema))   # the gate cannot change as the token grows
    end

    endswith(rstrip(token), ',') && error("""
        Trailing comma in value: $token
        A space after a comma ends the value.
        """ * LIST_HINT)

    return token, i
end

"""
    heal_args(raw_args, schema) -> Vector{String}

Rejoin list values that the shell split on whitespace. A `-D` payload whose key
the schema declares a list absorbs following tokens while its value has an
unclosed quote or bracket — the closing delimiter marks the end of the value, so
absorbed tokens may look like anything: `-Dsysimg=[a, --selfsign]` yields a
two-element list.

Everything else passes through untouched. A value only completes itself where a
list was expected, so `--filter key=[a` keeps its bracket and cannot swallow the
option after it, and `-Dbundler=[a` is a string that happens to start with one.

A comma is a separator, not a continuation signal. A value left ending in one is
rejected, as is one carrying a bracket that closes nothing: both are malformed
lists rather than requests to keep absorbing.
"""
function heal_args(raw_args, schema)
    tokens = map(String, raw_args)
    out = String[]

    i = 1
    while i <= length(tokens)
        token, i = absorb(tokens, i, isempty(out) ? "" : out[end], schema)
        push!(out, token)
        i += 1
    end

    return out
end


### Normalisation

"""Whether `token` introduces an option: a `--` or `-D` prefix, or an exact short alias."""
isoption(token, short_options) =
    startswith(token, "--") || startswith(token, "-D") || haskey(short_options, token)

"""
    normalize_args(tokens; short_options) -> Vector{Arg}

Turn tokens into `option => value` pairs. Attached and detached forms are
equivalent, and only the first `=` separates option from value:

    --password=foo=bar   ⇒  "--password" => "foo=bar"
    --password foo=bar   ⇒  "--password" => "foo=bar"
    -Dbundler=juliaimg   ⇒  "-D"         => "bundler=juliaimg"
    -D bundler=juliaimg  ⇒  "-D"         => "bundler=juliaimg"
    --selfsign           ⇒  "--selfsign" => nothing
    -h                   ⇒  "--help"     => nothing

An option takes the following token as its value unless that token is itself an
option. Tokens appearing where no option is open are emitted as
`token => nothing`. Values have one matching pair of outer quotes removed. The
`-D` payload is left untouched — `unquote` runs later, per list element, during
type coercion.

This function pairs tokens and nothing else: it takes each one as given, so a
value keeps its brackets, commas and quotes, and never reaches across a shell
split. Rejoining split list values is `heal_args`, a separate pass that
`parse_args` runs first because it needs the schema.

Which tokens count as options is asymmetric, and it constrains what a detached
value can be. Any token starting with `--` or `-D` is an option, so a value
beginning with either can never be adopted: `--target-name --weird` yields two
valueless options rather than a name. Short options are matched exactly instead,
so only the literal token `-h` is an option while `-hunter2` and `-secret`
remain values. The attached form bypasses this check entirely and is the escape
hatch for both cases — write `--target-name=--weird` or `--password=-h`. None of
it applies inside a healed value, where an open bracket or trailing comma has
already joined the tokens before this function sees them, so
`-Dsysimg=[a, --selfsign]` keeps `--selfsign` as a list element.
"""
function normalize_args(tokens; short_options = Dict{String, String}())
    tokens = map(String, tokens)
    out = Arg[]

    i = 1
    while i <= length(tokens)
        token = tokens[i]
        i += 1

        if haskey(short_options, token)              # boolean short flag, takes no value
            push!(out, String(short_options[token]) => nothing)
            continue
        elseif token == "--" || !isoption(token, short_options)
            push!(out, token => nothing)             # marker, positional, or a stray value
            continue
        end

        if startswith(token, "-D")
            option = "-D"
            payload = SubString(token, 3)            # "" for a bare -D, as in list_payload
            value = isempty(payload) ? nothing : String(payload)
        else
            key, raw = splitpair(token)
            option = String(key)
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

"""
    parse_extra_args(defines, schema) -> Dict{String, Any}

Read `key=value` payloads against the schema. An unknown key is an error with
near misses suggested; a known one has its value coerced to the type of its
default. A bare `key` stands for `key=true` and is only allowed where that
default is a `Bool`.
"""
function parse_extra_args(defines, schema::AbstractDict)
    overrides = Dict{String, Any}()

    for define in defines
        key, raw = splitpair(define)
        key = String(strip(key))

        haskey(schema, key) || error(unknown_key_message(key, schema))
        default = schema[key]

        if raw === nothing
            default isa Bool || error("preference '$key' expects $(type_name(default)); " *
                                      "bare keys are only allowed for booleans. Use -D$key=<value>.")
            overrides[key] = true
        else
            overrides[key] = coerce(strip(raw), default, key)
        end
    end

    return overrides
end

"""
    coerce(value, default, key) -> Any

Interpret `value` according to the type of `default`. The string is never
inspected to guess a type; the schema decides.

Quotes come off at the leaf, once. A list therefore sees its payload as written:
a wholly quoted one is a single element, and quotes inside a bracketed one
protect the commas they enclose.
"""
function coerce(value::AbstractString, default::AbstractVector, key)
    body = strip(value)
    elem_default = isempty(default) ? "" : first(default)

    if isquoted(body)
        inner = strip(unquote(body))
        isempty(inner) && return similar(default, 0)
        islist(inner) || return [coerce(inner, elem_default, key)]
        body = inner
    end

    islist(body) && (body = strip(chop(body, head = 1, tail = 1)))
    isempty(body) && return similar(default, 0)

    return [coerce(p, elem_default, key) for p in split_elements(body)]
end

coerce(value::AbstractString, ::AbstractString, key) = String(unwrap(value))

function coerce(value::AbstractString, ::Bool, key)
    v = unwrap(value)
    v in ("true", "false") ||
        error("preference '$key' expects true or false, got '$v'")
    return v == "true"
end

function coerce(value::AbstractString, default::Integer, key)
    v = unwrap(value)
    n = tryparse(typeof(default), v)
    n === nothing && error("preference '$key' expects an integer, got '$v'")
    return n
end

function coerce(value::AbstractString, default::AbstractFloat, key)
    v = unwrap(value)
    x = tryparse(typeof(default), v)
    x === nothing && error("preference '$key' expects a number, got '$v'")
    return x
end

coerce(::AbstractString, default, key) =
    error("preference '$key' has a default of type $(typeof(default)), which cannot be set from the command line")

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


### Entry point

"""
    parse_args(raw_args; schema, short_options) -> (options, overrides)

Split `raw_args` into `option => value` pairs and `-Dkey=value` preference
overrides. `schema` maps preference names to defaults whose types drive
coercion — and, before that, decide which values may be rejoined across a shell
split. `short_options` maps single-dash aliases to their long form, as in
`Dict("-h" => "--help")`.
"""
function parse_args(raw_args; schema::AbstractDict = Dict{String, Any}(), short_options = Dict{String, String}())
    options = Arg[]
    defines = String[]

    for (key, value) in normalize_args(heal_args(raw_args, schema); short_options)
        if key == "-D"
            value === nothing && error("-D expects key=value, e.g. -Dbundler=juliaimg")
            push!(defines, value)
        else
            push!(options, key => value)
        end
    end

    return options, parse_extra_args(defines, schema)
end

end
