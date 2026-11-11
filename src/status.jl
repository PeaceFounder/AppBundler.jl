module PreferenceStatus
    @enum T ERROR EXPLICIT INFERRED DEFAULT
end

const PreferenceEntry = @NamedTuple{key::String, value::Any, status::PreferenceStatus.T, from::Tuple{Vararg{String}}}

"""How a resolved preference is shown: set by the user, a shipped default, or inferred from the project."""
function preference_status(entry)
    !isnothing(entry.problem) && return PreferenceStatus.ERROR
    entry.origin == "inferred" && return PreferenceStatus.INFERRED
    entry.origin in ("defaults", nothing) && return PreferenceStatus.DEFAULT
    return PreferenceStatus.EXPLICIT
end

"""
    preferences_status(project; defines = []) -> Vector{PreferenceEntry}

Every preference with its final value and where it came from, as `appbundler status`
shows them: `EXPLICIT` when the project's `LocalPreferences.toml` or the command line
set it, `DEFAULT` from AppBundler's own `LocalPreferences.toml`, `INFERRED` from the project, and
`ERROR` when it is unknown, invalid or could not be inferred. Never throws.
"""
function preferences_status(project; defines = Pair{String, Any}[], schema = LOCAL_PREFERENCES_SCHEMA,
                            layers = preference_layers(project; defines))

    entries = PreferenceEntry[(key = e.key, value = e.value, status = preference_status(e), from = e.from)
                              for e in Knobs.status(schema, layers)]

    return sort!(entries; by = e -> (e.status, e.key))
end


format_value(v::AbstractVector) = "[" * join(map(format_value, v), ", ") * "]"
format_value(v) = repr(v)

function print_preferences(io::IO, entries::AbstractVector{PreferenceEntry})
    missing_entries = filter(e -> e.status == PreferenceStatus.ERROR && isnothing(e.value), entries)
    value_entries   = filter(e -> !(e.status == PreferenceStatus.ERROR && isnothing(e.value)), entries)

    width = maximum(e -> length(e.key), value_entries; init = 0)

    for e in value_entries
        marker = e.status == PreferenceStatus.ERROR    ? "! " :
                 e.status == PreferenceStatus.INFERRED ? "* " : "  "
        line = string(marker, rpad(e.key, width), " = ", format_value(e.value))

        if e.status == PreferenceStatus.ERROR
            printstyled(io, line; color = :red)
        elseif e.status == PreferenceStatus.EXPLICIT
            print(io, line)
        else
            printstyled(io, line; color = :light_black)
        end
        # Which preferences an inferred value was computed from
        isempty(e.from) || printstyled(io, "  (from ", join(e.from, ", "), ")"; color = :light_black)
        println(io)
    end

    if !isempty(missing_entries)
        println(io)
        printstyled(io, "! Could not be inferred:\n"; color = :red)
        print_wrapped(io, [e.key for e in missing_entries]; indent = 4, color = :red)
    end
end

# Print words separated by ", ", wrapping lines at the terminal width
function print_wrapped(io::IO, words; indent = 0, color = :normal)
    max_width = displaysize(io)[2]
    pad = " "^indent
    line = pad

    for (i, word) in enumerate(words)
        piece = i < length(words) ? word * ", " : word
        if length(line) + length(piece) > max_width && line != pad
            printstyled(io, rstrip(line), '\n'; color)
            line = pad
        end
        line *= piece
    end
    printstyled(io, line, '\n'; color)
end


function print_preferences(io::IO, project_dir; defines = Pair{String, Any}[])

    entries = preferences_status(project_dir; defines)
    print_preferences(io, entries)

    return
end

print_preferences(project_dir) = print_preferences(stdout, project_dir)

isoverridden(value) = value === true || (value isa Tuple && any(((_, v),) -> isoverridden(v), value))

function print_overrides(io::IO, entries::Tuple; indent::Int = 0)
    for (key, value) in entries
        generated = value isa AbstractString
        prefix = indent == 0 ? "" : " "^(indent - 2) * (generated ? "* " : "  ")

        if value isa Tuple
            if isoverridden(value)
                println(io, prefix, key, "/")
            else
                printstyled(io, prefix, key, "/"; color = :light_black)
                println(io)
            end
            print_overrides(io, value; indent = indent + 2)
        elseif value === true
            println(io, prefix, key)
        else
            printstyled(io, prefix, key; color = :light_black)
            if generated && !isempty(value)
                if get(io, :color, false)
                    print(io, "\e[2;90m  [source = ", value, "]\e[0m")
                else
                    print(io, "  [source = ", value, "]")
                end
            end
            println(io)
        end
    end
end

print_overrides(io::IO, entry::Pair; kwargs...) = print_overrides(io, (entry,); kwargs...)
print_overrides(entries::Union{Tuple,Pair}; kwargs...) = print_overrides(stdout, entries; kwargs...)

print_overrides(io::IO, project_dir::AbstractString) = print_overrides(io, override_status(project_dir))
print_overrides(project_dir::AbstractString) = print_overrides(stdout, project_dir)
