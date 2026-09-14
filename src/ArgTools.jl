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

"""Whether a value closes every quote and bracket it opens."""
function balanced(v::AbstractString)
    _, open_quote, depth = scan(v)
    return open_quote === nothing && depth <= 0
end

"""Whether the value part of `token` (everything after the first `=`) is balanced."""
function token_balanced(token::AbstractString)
    _, value = splitpair(token)
    return value === nothing || balanced(value)
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
    heal_args(raw_args) -> Vector{String}

Rejoin option values that the shell split on whitespace. A token containing `=`
absorbs following tokens while it has an unclosed quote or bracket — the closing
delimiter marks the end of the value, so absorbed tokens may look like anything:
`-Dsysimg=[a, --selfsign]` yields a two-element list.

A comma is a separator, not a continuation signal. A value left ending in one is
rejected: write the list without spaces, or bracket it so its end is explicit.
"""
function heal_args(raw_args)
    tokens = map(String, raw_args)
    out = String[]

    i = 1
    while i <= length(tokens)
        token = tokens[i]

        if occursin('=', token)
            while !token_balanced(token)
                i += 1
                i > length(tokens) && error("""
                    Unterminated value: $token
                    Missing a closing ']' or '"'.
                    """ * LIST_HINT)
                token *= " " * tokens[i]
            end
            endswith(rstrip(token), ',') && error("""
                Trailing comma in value: $token
                A space after a comma ends the value.
                """ * LIST_HINT)
        end

        push!(out, token)
        i += 1
    end

    return out
end


### Normalisation

isoption(token, short_options) =
    startswith(token, "--") || startswith(token, "-D") || haskey(short_options, token)

"""
    normalize_args(raw_args; short_options) -> Vector{Arg}

Turn raw ARGS into `option => value` pairs. Attached and detached forms are
equivalent, and only the first `=` separates option from value:

    --password=foo=bar   ⇒  "--password" => "foo=bar"
    --password foo=bar   ⇒  "--password" => "foo=bar"
    -Dbundler=juliaimg   ⇒  "-D"         => "bundler=juliaimg"
    -D bundler=juliaimg  ⇒  "-D"         => "bundler=juliaimg"
    --selfsign           ⇒  "--selfsign" => nothing
    -h                   ⇒  "--help"     => nothing

An option takes the following token as its value unless that token is itself an
option. Tokens appearing where no option is open are emitted as
`token => nothing`. Values are healed first (see `heal_args`) and have one
matching pair of outer quotes removed. The `-D` payload is left untouched —
`unquote` runs later, per list element, during type coercion.

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
function normalize_args(raw_args; short_options = Dict{String, String}())
    tokens = heal_args(raw_args)
    out = Arg[]

    i = 1
    while i <= length(tokens)
        token = tokens[i]
        i += 1

        if !isoption(token, short_options)
            push!(out, token => nothing)             # positional, or a stray value
            continue
        elseif haskey(short_options, token)          # boolean short flag, takes no value
            push!(out, String(short_options[token]) => nothing)
            continue
        elseif token == "--"                         # end-of-options marker
            push!(out, "--" => nothing)
            continue
        end

        if startswith(token, "-D")
            option = "-D"
            value = length(token) > 2 ? token[3:end] : nothing
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

"""Remove one layer of matching outer quotes, if the shell left any behind."""
function unquote(s::AbstractString)
    length(s) >= 2 || return s
    (s[1] == s[end] && (s[1] == '"' || s[1] == '\'')) || return s
    return s[nextind(s, 1):prevind(s, lastindex(s))]
end


### Coercion against the schema

function parse_extra_args(defines, schema::Dict)
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
            overrides[key] = coerce(unquote(strip(raw)), default, key)
        end
    end

    return overrides
end

"""
    coerce(value, default, key) -> Any

Interpret `value` according to the type of `default`. The string is never
inspected to guess a type; the schema decides.
"""
function coerce(value::AbstractString, default::AbstractVector, key)
    body = strip(value)
    if startswith(body, '[') && endswith(body, ']')
        body = strip(body[nextind(body, 1):prevind(body, lastindex(body))])
    end
    isempty(body) && return similar(default, 0)

    elem_default = isempty(default) ? "" : first(default)
    return [coerce(unquote(strip(p)), elem_default, key) for p in split_elements(body)]
end

coerce(value::AbstractString, ::AbstractString, key) = String(value)

function coerce(value::AbstractString, ::Bool, key)
    value in ("true", "false") ||
        error("preference '$key' expects true or false, got '$value'")
    return value == "true"
end

function coerce(value::AbstractString, default::Integer, key)
    n = tryparse(typeof(default), value)
    n === nothing && error("preference '$key' expects an integer, got '$value'")
    return n
end

function coerce(value::AbstractString, default::AbstractFloat, key)
    x = tryparse(typeof(default), value)
    x === nothing && error("preference '$key' expects a number, got '$value'")
    return x
end

coerce(::AbstractString, default, key) =
    error("preference '$key' has a default of type $(typeof(default)), which cannot be set from the command line")

type_name(::AbstractString) = "a string"
type_name(::Bool) = "true or false"
type_name(::Integer) = "an integer"
type_name(::AbstractFloat) = "a number"
type_name(::AbstractVector) = "a list"
type_name(x) = "a $(typeof(x))"

function unknown_key_message(key, schema)
    threshold = max(2, length(key) ÷ 4)
    near = sort!([string(k) for k in keys(schema) if edit_distance(key, k) <= threshold])
    msg = "unknown preference '$key'"
    isempty(near) || (msg *= "\n       did you mean " * join(("'$k'" for k in near), ", ", " or ") * "?")
    return msg
end

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
coercion; `short_options` maps single-dash aliases to their long form, as in
`Dict("-h" => "--help")`.
"""
function parse_args(raw_args; schema::Dict = Dict{String, Any}(), short_options = Dict{String, String}())
    options = Arg[]
    defines = String[]

    for (key, value) in normalize_args(raw_args; short_options)
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
