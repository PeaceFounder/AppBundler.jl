module CLIParser

"""
    is_balanced(s) -> Bool

True when `s` contains no unclosed quote and no unclosed bracket, i.e. the
shell did not split a `-D` value across multiple argv entries.
"""
function is_balanced(s::AbstractString)
    quote_char = nothing
    depth = 0
    escaped = false
    for c in s
        if escaped
            escaped = false
        elseif c == '\\'
            escaped = true
        elseif quote_char !== nothing
            c == quote_char && (quote_char = nothing)
        elseif c == '"' || c == '\''
            quote_char = c
        elseif c == '[' || c == '{'
            depth += 1
        elseif c == ']' || c == '}'
            depth -= 1
        end
    end
    return quote_char === nothing && depth <= 0
end


ends_open(s) = endswith(rstrip(s), ',')

function heal_args(raw_args)
    out = String[]
    i = 1
    while i <= length(raw_args)
        tok = String(raw_args[i])
        if occursin('=', tok)
            while !is_balanced(tok) || ends_open(tok)
                i += 1
                i > length(raw_args) && error("""
                    Unterminated value: $tok
                    It ends with a comma, or is missing a closing ']' or '"'.
                    Write the value without spaces, or quote the whole option:
                        -Dkey=a,-b        or        -D 'key=[a, -b]'
                    """)
                tok *= " " * raw_args[i]
            end
        end
        push!(out, tok)
        i += 1
    end
    return out
end


const Arg = Pair{String, Union{String, Nothing}}

isoption(tok) = startswith(tok, "--") || startswith(tok, "-D")

"""
    normalize_args(raw_args) -> Vector{Arg}

Turn raw ARGS into `option => value` pairs. Attached and detached forms are
equivalent, and only the first `=` separates option from value:

    --password=foo=bar   ⇒  "--password" => "foo=bar"
    --password foo=bar   ⇒  "--password" => "foo=bar"
    -Dbundler=juliaimg   ⇒  "-D"         => "bundler=juliaimg"
    -D bundler=juliaimg  ⇒  "-D"         => "bundler=juliaimg"
    --selfsign           ⇒  "--selfsign" => nothing

An option takes the following token as its value unless that token is itself an
option. Tokens appearing where no option is open are emitted as `token =>
nothing`.

Values are healed first: a token containing `=` keeps absorbing following
tokens while it has an unclosed quote or bracket, or ends in a comma.
"""
function normalize_args(raw_args)
    tokens = heal_args(raw_args)
    out = Arg[]

    i = 1
    while i <= length(tokens)
        tok = tokens[i]

        if !isoption(tok)
            push!(out, tok => nothing)     # positional, or a stray value
            i += 1
            continue
        end

        if startswith(tok, "-D") && !startswith(tok, "--")
            option = "-D"
            value = length(tok) > 2 ? tok[3:end] : nothing
        else
            j = findfirst('=', tok)
            option = j === nothing ? tok : tok[1:prevind(tok, j)]
            value  = j === nothing ? nothing : tok[nextind(tok, j):end]
        end

        # Detached form: adopt the next token unless it is another option.
        if value === nothing && i < length(tokens) && !isoption(tokens[i+1])
            i += 1
            value = tokens[i]
        end

        push!(out, option => (value === nothing ? nothing : unquote(value)))
        i += 1
    end

    return out
end


### Extra argument coercion according to schema

function parse_extra_args(args::Vector{String}, schema::Dict)

    overrides = Dict{String, Any}()

    for arg in args
        j = findfirst('=', arg)
        key = j === nothing ? strip(arg) : strip(arg[1:prevind(arg, j)])
        raw = j === nothing ? nothing : strip(arg[nextind(arg, j):end])

        haskey(schema, key) || error(unknown_key_message(key, schema))

        default = schema[key]

        if raw === nothing
            default isa Bool || error("preference '$key' expects $(type_name(default)); " *
                                      "bare keys are only allowed for booleans. Use -D$key=<value>.")
            overrides[key] = true
        else
            overrides[key] = coerce(unquote(raw), default, key)
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
    return [coerce(unquote(strip(p)), elem_default, key) for p in split(body, ',')]
end

coerce(value::AbstractString, ::AbstractString, key) = String(value)

function coerce(value::AbstractString, ::Bool, key)
    value in ("true", "false") ||
        error("preference '$key' expects true or false, got '$value'")
    return value == "true"
end

function coerce(value::AbstractString, ::Integer, key)
    n = tryparse(Int, value)
    n === nothing && error("preference '$key' expects an integer, got '$value'")
    return n
end

function coerce(value::AbstractString, ::AbstractFloat, key)
    x = tryparse(Float64, value)
    x === nothing && error("preference '$key' expects a number, got '$value'")
    return x
end

"""Remove one layer of matching outer quotes, if the shell left any behind."""
function unquote(s::AbstractString)
    length(s) >= 2 || return s
    (s[1] == s[end] && (s[1] == '"' || s[1] == '\'')) || return s
    return s[nextind(s, 1):prevind(s, lastindex(s))]
end

type_name(::AbstractString) = "a string"
type_name(::Bool) = "true or false"
type_name(::Integer) = "an integer"
type_name(::AbstractFloat) = "a number"
type_name(::AbstractVector) = "a list"

function unknown_key_message(key, schema)
    near = [k for k in keys(schema) if edit_distance(key, k) <= max(2, length(key) ÷ 4)]
    msg = "unknown preference '$key'"
    isempty(near) || (msg *= "\n       did you mean " * join(("'$k'" for k in sort(near)), ", ", " or ") * "?")
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


end
