"""
    Knobs

Layered, explainable preferences for command-line tools. Everything is a flat
`"dotted.key" => value` pair:

    options, defines = parse_options(ARGS)               # argv -> option => value pairs, no schema
    for (option, raw) in options ... end                 # the caller's own loop; may push!(defines, ...)

    layers = ["inferred"              => [ "app_exe" => Rule("app_name") do x ... end, ... ],
              "defaults"              => flatten(TOML.parsefile("defaults.toml")["MyTool"]),
              "LocalPreferences.toml" => flatten(TOML.parsefile(joinpath(project, "LocalPreferences.toml"))["MyTool"]),
              "command line"          => defines]

    prefs   = resolve(schema, layers)     # Dict{String,Any}; throws listing every problem
    entries = status(schema, layers)      # one entry per key: value, origin, inputs, problem

The schema is flat too: dotted keys mapped to a spec, which is a type (`Bool`,
`Int`, `String`, `Vector{String}`, `Union{String, Nothing}`, …), a tuple of
allowed values, or a custom spec with its own [`coerce`](@ref) method:

    Dict(
        "compress"        => Bool,
        "juliaimg.sysimg" => Vector{String},
        "dmg.backend"     => ("xorriso", "hfsplus"),
    )

Nesting exists only at the edges: [`flatten`](@ref) turns a parsed table into
pairs and [`nest`](@ref) turns pairs back into nested tables. Knobs reads no
files itself; the caller parses them with the format of its choice.
"""
module Knobs

export parse_options, coerce, CoercionError, Rule, resolve, status, print_status, flatten, nest

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

    return options, Vector{Pair{String, Any}}(defines)
end


############################################################################
### Helpers for the caller's option loop
############################################################################

"""
    value(option, raw) -> String
    value(option, raw, spec) -> Any

The value given to `option`, for use inside the caller's loop over the options
from [`parse_options`](@ref). Errors when the option was given without one.
With a `spec` the text is converted like a preference, and a bad value is
reported against the option:

    for (option, raw) in options
        if option == "--build-dir"
            build_dir = Knobs.value(option, raw)
        elseif option == "--jobs"
            jobs = Knobs.value(option, raw, Int)    # "--jobs expects an integer, got 'many'"
        ...
"""
function value(option, raw)
    raw === nothing && error("$option requires a value")
    return raw
end

function value(option, raw, spec)
    text = value(option, raw)
    try
        return coerce(text, spec)
    catch err
        err isa CoercionError || rethrow()
        error("$option $(err.msg)")
    end
end

"""
    flag(option, raw)

Check that `option` was given as a bare flag. Errors when a value was attached,
as in `--force=yes`.
"""
flag(option, raw) = raw === nothing || error("$option does not take a value, got '$raw'")


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
spec_name(::Type{Union{Nothing, T}}) where {T} = spec_name(T) * " or nothing"
spec_name(::Type{Symbol}) = "a name"
spec_name(spec) = "a $spec"

"""Report an unknown preference, naming any schema key within a few edits of it."""
function unknown_key_message(key, schema)
    near = near_keys(key, schema)
    msg = "unknown preference '$key'"
    isempty(near) || (msg *= "\n       did you mean " * join(("'$k'" for k in near), ", ", " or ") * "?")
    return msg
end

"""Schema keys within a few edits of `key`."""
function near_keys(key, schema)
    threshold = max(2, length(key) ÷ 4)
    return sort!([string(k) for k in keys(schema) if edit_distance(key, k) <= threshold])
end

"""`"; did you mean 'compress'?"`, or `""` when no schema key is close."""
function did_you_mean(key, schema)
    near = near_keys(key, schema)
    return isempty(near) ? "" : "; did you mean " * join(("'$k'" for k in near), ", ", " or ") * "?"
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

Coerce `key => value` pairs, such as the defines from [`parse_options`](@ref)
plus whatever the caller's option loop pushed, against a flat `schema` of dotted
keys, keeping their order. An unknown key is an error with near misses
suggested, and a bad value is an error naming its key. Values may be raw text
or already typed; see [`coerce(value, spec)`](@ref).

A key given more than once keeps its last value. A key the schema declares a
list accumulates instead: a bare text value appends to the list, while a
bracketed one, or a typed vector, resets it to that value. The key keeps the
position of its first occurrence.

    -Dsysimg=a -Dsysimg=b           # sysimg = ["a", "b"]
    -Dsysimg=a -Dsysimg=[b, c]      # sysimg = ["b", "c"]
    -Dsysimg=[a] -Dsysimg=b         # sysimg = ["a", "b"]
    -Dsysimg=a -Dsysimg=[]          # sysimg = []

    options, defines = parse_options(ARGS)
    prefs = coerce(defines, schema)
"""
function coerce(defines::AbstractVector{<:Pair}, schema::AbstractDict)
    collected = collect_layer(defines, schema)
    isempty(collected.problems) || error(first(collected.problems).second.long)
    return Pair{String, Any}[key => collected.values[key] for key in collected.order]
end

"""
    collect_layer(pairs, schema) -> (; order, values, problems)

Fold one layer's pairs into a value per key, applying the list rules of
[`coerce(defines, schema)`](@ref). [`Rule`](@ref) values are not coerced: rules
for the same key collect into a vector of alternatives. Problems are returned
rather than thrown, as `key => (; short, long)`: the short message for an entry
that already names its key, the long one for an error that must.
"""
function collect_layer(pairs, schema::AbstractDict)
    order = String[]
    values = Dict{String, Any}()
    problems = Pair{String, NamedTuple{(:short, :long), Tuple{String, String}}}[]

    for (key, raw) in pairs
        key = String(key)
        haskey(values, key) || push!(order, key)

        if !haskey(schema, key)
            values[key] = raw
            push!(problems, key => (short = "unknown preference" * did_you_mean(key, schema),
                                    long = unknown_key_message(key, schema)))
            continue
        end
        spec = schema[key]

        if raw isa Rule
            previous = get(values, key, nothing)
            values[key] = previous isa Vector{Rule} ? push!(previous, raw) : Rule[raw]
            continue
        end

        value = try
            coerce(raw isa AbstractString ? strip(raw) : raw, spec)
        catch err
            err isa CoercionError || rethrow()
            values[key] = raw
            push!(problems, key => (short = err.msg, long = "preference '$key' $(err.msg)"))
            continue
        end

        previous = get(values, key, nothing)
        if islisttype(spec) && previous isa AbstractVector && !resets_list(raw)
            values[key] = vcat(previous, value)          # bare value: append
        else
            values[key] = value                          # first, scalar, or reset
        end
    end

    return (; order, values, problems)
end

"""Whether a schema spec describes a list-valued preference."""
islisttype(spec) = spec isa Type && spec <: AbstractVector

"""
Whether the raw value of a list preference resets the list instead of appending
to it: text written as an explicit list (a wholly quoted list counts, as it does
in list coercion), or any value that is not text at all.
"""
function resets_list(raw)
    raw === nothing && return false
    raw isa AbstractString || return true
    s = strip(raw)
    isquoted(s) && (s = strip(unquote(s)))
    return islist(s)
end


"""
    coerce(value, spec) -> Any

Convert `value` to what the schema `spec` describes, or throw a
[`CoercionError`](@ref). This one function serves every source: raw text from
the command line, values parsed from TOML, and typed values a caller pushed.

- Text is interpreted, never inspected to guess a type: the spec decides. It is
  trimmed and one layer of matching quotes comes off, so `-Dname="a b"` and
  `name = "a b"` mean the same.
- A typed value is checked, and converted where TOML is loose: an array becomes
  `Vector{eltype}` element by element, an integer becomes a float.
- `nothing` — a bare `-Dkey` — stands for `true` where the spec is `Bool`, and
  for `nothing` where the spec admits it, as in `Union{String, Nothing}`.

A custom spec needs only one method. It is called with text and TOML values
alike:

    struct HexColor end
    function Knobs.coerce(value, ::HexColor)
        value isa AbstractString && is_hex_color(value) && return String(value)
        throw(Knobs.CoercionError("expects a hex colour like #f3f3f3, got \$(repr(value))"))
    end

Lists in text: a wholly quoted payload is a single element, and quotes inside a
bracketed one protect the commas they enclose. Elements are coerced to
`eltype(spec)`, so `Vector{Int}` does not quietly become a list of strings.
A blank element is an error — `[a,,b]` and `[,a]` are malformed rather than
carriers of an empty string, which is written `["", a]`. The one exception is a
single trailing comma inside brackets, which is conventional and ignored. A
bracket or quote left open is an error too: one shell word is one value, so
`-Dsysimg=[a, b]` must be quoted or written without the space.
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

# A typed list, as TOML delivers it (`[]` parses to `Vector{Any}`): convert element by element
coerce(value::AbstractVector, ::Type{T}) where {T <: AbstractVector} = eltype(T)[coerce(x, eltype(T)) for x in value]

coerce(value::AbstractString, ::Type{<:AbstractString}) = String(unwrap(value))

coerce(value::AbstractString, ::Type{Any}) = String(unwrap(value))

coerce(value::AbstractString, ::Type{Symbol}) = Symbol(unwrap(value))

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

# TOML writes `1` for a float field as readily as `1.0`
coerce(value::Union{Integer, AbstractFloat}, ::Type{T}) where {T <: AbstractFloat} =
    value isa Bool ? throw(CoercionError("expects a number, got $value")) : T(value)

# Allowed values: text must equal one of the options as written; the option itself is returned
function coerce(value::AbstractString, options::Tuple)
    v = unwrap(value)
    i = findfirst(o -> string(o) == v, options)
    i === nothing && throw(CoercionError("expects $(spec_name(options)), got '$v'"))
    return options[i]
end

function coerce(value, options::Tuple)
    value in options && return value
    throw(CoercionError("expects $(spec_name(options)), got $(repr(value))"))
end

# An optional key: `nothing` stays `nothing`, anything else is coerced to the inner type
coerce(::Nothing, ::Type{Union{Nothing, T}}) where {T} = nothing
coerce(value, ::Type{Union{Nothing, T}}) where {T} = coerce(value, T)

# A bare `-Dkey` stands for `true`, and only for booleans
coerce(::Nothing, ::Type{Bool}) = true

# A typed value of the right type passes as it is
function coerce(value, spec::Type)
    value isa spec && return value
    value === nothing &&
        throw(CoercionError("expects $(spec_name(spec)); bare keys are only allowed for booleans"))
    throw(CoercionError("expects $(spec_name(spec)), got $(repr(value))"))
end

function coerce(value, spec)
    value === nothing &&
        throw(CoercionError("expects $(spec_name(spec)); bare keys are only allowed for booleans"))
    throw(CoercionError("has a schema entry $(repr(spec)), which has no coerce method for $(repr(value))"))
end


############################################################################
### Nested tables <-> flat pairs
############################################################################

"""
    flatten(table) -> Vector{Pair{String, Any}}

Map every value in a nested table to its dotted path, sorted by key:
`Dict("dmg" => Dict("backend" => "xorriso"))` becomes `["dmg.backend" => "xorriso"]`.
Tables themselves get no entry.
"""
function flatten(table::AbstractDict, prefix::AbstractString = "")
    flat = Pair{String, Any}[]
    for (key, value) in table
        path = isempty(prefix) ? String(key) : "$prefix.$key"
        if value isa AbstractDict
            append!(flat, flatten(value, path))
        else
            push!(flat, path => value)
        end
    end
    return sort!(flat; by = first)
end

"""
    nest(pairs) -> Dict{String, Any}

Inverse of [`flatten`](@ref): turn `"juliaimg.sysimg" => ["GtkApp"]` into
`"juliaimg" => Dict("sysimg" => ["GtkApp"])`. Accepts any iterable of pairs,
including the `Dict` returned by [`resolve`](@ref).
"""
function nest(pairs)
    nested = Dict{String, Any}()
    for (key, value) in pairs
        parts = split(key, '.')
        node = nested
        for part in parts[1:end-1]
            node = get!(Dict{String, Any}, node, String(part))
            node isa AbstractDict || error("cannot nest '$key': '$part' already holds a value")
        end
        haskey(node, parts[end]) && node[parts[end]] isa AbstractDict &&
            error("cannot nest '$key': it already holds a table")
        node[String(parts[end])] = value
    end
    return nested
end

############################################################################
### Rules: values computed from other values
############################################################################

"""
    Rule(f, inputs...)

A value computed from the final values of other keys, placed in a layer like
any other value. `inputs` name the keys it is derived from; `f` receives their
values in that order, and takes no arguments when there are none. With a
do-block the function comes first and the inputs follow:

    "app_name" => Rule() do; get_project_name(project_toml) end,
    "app_exe"  => Rule("app_name") do name; lowercase(name) end,
    "command"  => Rule("bundler", "app_exe") do bundler, exe; ["bin/\$exe"] end,

- A rule is a value: the highest layer that mentions a key wins, so a plain
  value in a higher layer replaces the rule.
- Several rules for the same key in one layer are alternatives, tried in order.
  A rule is skipped without being called when one of its inputs is `nothing`,
  and declines by returning `nothing`; the next alternative is then tried.
- An input that failed is not skipped: the key reports what it needed.
- The result is coerced against the key's spec like any other value.
"""
struct Rule
    f::Any
    inputs::Tuple{Vararg{String}}
    Rule(f, inputs::AbstractString...) = new(f, String.(inputs))
end

Base.show(io::IO, rule::Rule) = print(io, "Rule(", join(repr.(rule.inputs), ", "), ")")


############################################################################
### Resolution: layers -> one value per key, with its origin
############################################################################

"""A failed key: the message says why, including which layer or input."""
struct Failure
    msg::String
end

"""Split a layer into its label (or index) and its pairs."""
layer_parts(layer::Pair, i) = (first(layer), last(layer))
layer_parts(layer, i) = (i, layer)

layer_name(label::Integer) = "layer $label"
layer_name(label) = string(label)

function evaluate(schema::AbstractDict, layers)
    winner = Dict{String, Any}()      # key => coerced value, or Vector{Rule}
    origin = Dict{String, Any}()      # key => label of the layer that set it
    problems = Dict{String, String}() # key => message, for values a layer got wrong

    for (i, layer) in enumerate(layers)
        label, pairs = layer_parts(layer, i)
        collected = collect_layer(pairs, schema)
        for key in collected.order
            winner[key] = collected.values[key]
            origin[key] = label
        end
        for (key, msg) in collected.problems
            problems[key] = "$(layer_name(label)): $(msg.short)"
        end
    end

    resolved = Dict{String, Any}()    # key => value (nothing when unset) or Failure
    from = Dict{String, Tuple{Vararg{String}}}()
    visiting = String[]

    function get_value(key)
        haskey(resolved, key) && return resolved[key]
        haskey(problems, key) && return (resolved[key] = Failure(problems[key]))

        if key in visiting
            cycle = join([visiting[findfirst(==(key), visiting):end]; key], " -> ")
            return Failure("dependency cycle: $cycle")
        end

        candidate = get(winner, key, nothing)
        candidate isa Vector{Rule} || return (resolved[key] = candidate)

        push!(visiting, key)
        result = try
            run_rules(key, candidate)
        finally
            pop!(visiting)
        end
        return (resolved[key] = result)
    end

    function run_rules(key, rules)
        for rule in rules
            inputs = Any[]
            for input in rule.inputs
                haskey(schema, input) || return Failure("rule input '$input' is not in the schema")
                v = get_value(input)
                v isa Failure && return Failure("needs $input: $(v.msg)")
                v === nothing && break
                push!(inputs, v)
            end
            length(inputs) < length(rule.inputs) && continue      # an input is nothing: skip

            v = try
                rule.f(inputs...)
            catch err
                return Failure("could not be inferred: " * sprint(showerror, err))
            end
            v === nothing && continue                               # declined

            try
                v = coerce(v, schema[key])
            catch err
                err isa CoercionError || rethrow()
                return Failure("rule result $(err.msg)")
            end
            from[key] = rule.inputs
            return v
        end
        return nothing
    end

    keys_all = sort!(collect(union(keys(schema), keys(winner))))
    entries = map(keys_all) do key
        v = get_value(key)
        problem = v isa Failure ? v.msg : nothing
        if isnothing(problem) && v === nothing && haskey(schema, key) && !allows_nothing(schema[key])
            problem = get(winner, key, nothing) isa Vector{Rule} ? "could not be inferred" : "is not set"
        end
        value = v isa Failure ? (winner[key] isa Vector{Rule} ? nothing : winner[key]) : v
        (key = key, value = value, origin = get(origin, key, nothing),
         from = get(from, key, ()), problem = problem)
    end

    return entries
end

allows_nothing(spec) = spec isa Type && Nothing <: spec

"""
    status(schema, layers) -> Vector of (; key, value, origin, from, problem)

Resolve `layers` like [`resolve`](@ref) without throwing, and report one entry
per key, sorted by key: every schema key, plus any unknown key a layer set.

- `value`: the final value; `nothing` when unset.
- `origin`: the label of the highest layer that mentions the key, whether with
  a value or a rule; its index when the layer is unlabelled; `nothing` if none does.
- `from`: the inputs of the rule that produced the value; empty for plain values.
- `problem`: `nothing`, or a message — an unknown key, a bad value (the value is
  kept), a rule that failed, or a required key left unset.
"""
status(schema::AbstractDict, layers) = evaluate(schema, layers)

"""
    resolve(schema, layers) -> Dict{String, Any}

Combine `layers`, lowest precedence first, into one value per key, with dotted
keys. A layer is a vector of `key => value` pairs, optionally labelled as
`label => pairs`; the label names the layer in errors and in [`status`](@ref).

1. Each layer's values are coerced against `schema`; [`Rule`](@ref)s pass through.
2. The layers are overlaid in order; for each key the highest layer wins.
3. Winning rules are evaluated lazily, in dependency order.
4. Every key whose spec does not admit `nothing` must now have a value.

Throws one error listing every problem. Keys left unset are absent from the result.
"""
function resolve(schema::AbstractDict, layers)
    entries = evaluate(schema, layers)
    problems = ["$(e.key): $(e.problem)" for e in entries if !isnothing(e.problem)]
    isempty(problems) || error("Invalid preferences:\n  " * join(problems, "\n  "))
    return Dict{String, Any}(e.key => e.value for e in entries if !isnothing(e.value))
end

############################################################################
### Printing: the resolved values, grouped by the layer that set them
############################################################################

format_value(v::AbstractVector) = "[" * join(map(format_value, v), ", ") * "]"
format_value(v) = repr(v)

"""
    print_status([io], schema, layers)
    print_status([io], entries; order)

Print every key with its final value, grouped under the layer that set it, the
highest-precedence layer first; a rule's inputs follow its value, and keys no
layer sets come last under `unset`. Problems are shown in red with their message,
so a misbehaving layer stands out:

    command line
      bundler           = "juliac"
    LocalPreferences.toml
    ! dmg.backend       = "hfs"
                          LocalPreferences.toml: expects one of 'xorriso' or 'hfsplus', got 'hfs'
    defaults
      compress          = true
    inferred
      app_exe           = "glapp"  (from app_name)

With `entries` from [`status`](@ref), `order` lists the layer labels to print, top
first; by default they follow their first appearance in `entries`.
"""
function print_status(io::IO, schema::AbstractDict, layers)
    labels = [first(layer_parts(layer, i)) for (i, layer) in enumerate(layers)]
    print_status(io, status(schema, layers); order = reverse(labels))
end

print_status(schema::AbstractDict, layers) = print_status(stdout, schema, layers)

function print_status(io::IO, entries::AbstractVector;
                      order = unique(e.origin for e in entries if !isnothing(e.origin)))

    width = maximum(e -> length(e.key), entries; init = 0)

    groups = [(layer_name(label), filter(e -> e.origin == label, entries)) for label in order]
    unset = filter(e -> isnothing(e.origin), entries)
    isempty(unset) || push!(groups, ("unset", unset))

    for (name, group) in groups
        isempty(group) && continue
        printstyled(io, name, '\n'; bold = true)
        for e in sort(group; by = e -> e.key)
            print_entry(io, e, width)
        end
    end
    return
end

print_status(entries::AbstractVector; kwargs...) = print_status(stdout, entries; kwargs...)

function print_entry(io::IO, e, width)
    failed = !isnothing(e.problem)
    color = failed ? :red : :normal

    value = failed && isnothing(e.value) ? "" : " = " * format_value(e.value)
    printstyled(io, failed ? "! " : "  ", rpad(e.key, width), value; color)
    isempty(e.from) || printstyled(io, "  (from ", join(e.from, ", "), ")"; color = :light_black)
    println(io)

    if failed
        pad = " "^(width + 5)
        printstyled(io, pad, replace(e.problem, "\n" => "\n" * pad), '\n'; color)
    end
    return
end

end # module Knobs
