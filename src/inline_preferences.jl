# Writing preferences into a project's LocalPreferences.toml: `appbundler inline . LocalPreferences.toml -Dkey=value`.
# Resolution itself lives in Knobs; writing back stays here, as text edits that keep the file's layout and comments.

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
    inline_preferences(destination, defines; section = "AppBundler")

Add `defines`, coerced `key => value` pairs with dotted keys, to `[section]` of the TOML
file at `destination`. Each new line is inserted into the table block it belongs to,
leaving the rest of the file untouched. Errors if any key is already set.
"""
function inline_preferences(destination, defines; section = "AppBundler")

    text = isfile(destination) ? read(destination, String) : ""
    current = Dict(Knobs.flatten(get(TOML.parse(text), section, Dict{String,Any}())))

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
    written = Dict(Knobs.flatten(get(TOML.parse(text), section, Dict{String,Any}())))
    misplaced = [key for (key, value) in defines if get(written, key, nothing) != value]
    isempty(misplaced) || error("Could not place " * join(misplaced, ", ") * " in $destination")

    write(destination, text)
    return destination
end
