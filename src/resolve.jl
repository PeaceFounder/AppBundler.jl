# Prototype: targets declared as a nested tree that mirrors the project layout.
#
#     resolve(project, "meta/dmg/Info.plist")  → "/…/meta/dmg/Info.plist"        (String)
#     resolve(project, "meta/dmg/icon.icns")   → "/…/meta/dmg/icon.icns"         (own file, String)
#                                              → IconSource("/…/meta/icon.svg")  (generated from icon)
#     resolve(project, "meta/dmg/DS_Store")    → DSStoreTOML("/…/DS_Store.toml") (generated from TOML)
#
# `resolve` returns `rule.format(path)` for the rule that matched, so a plain file is
# just a path. `locate` returns the same value plus where it came from, for status/inline.
#
# Untested sketch.

import Mustache, TOML
import IconTools, MsixPack, DmgPack

# ─────────────────────────────────────────────────────────────────────────────
# Formats: wrappers for files that are inputs to a conversion
# ─────────────────────────────────────────────────────────────────────────────


_path(x::String) = x
_path(x::IconSource) = x.path
_path(x::DSStoreTOML) = x.path

# ─────────────────────────────────────────────────────────────────────────────
# Rule
# ─────────────────────────────────────────────────────────────────────────────

"""
    Rule([format = String]; default, derive, template = false)

- `format`: applied to the path of a file found *for this target* (own file or
  default). `String` returns the path as is; `IconSource`/`DSStoreTOML` wrap it.
- `default`: built-in file, as a function returning a path (lazy, so package paths
  are looked up at run time rather than frozen at precompile time).
- `derive`: full target name this target is generated from when the project has no
  own file. The result then has *that* target's format.
- `template`: the file is a Mustache template (used by `inline --render`; staging
  code renders the fields it knows are templates).

Resolution order: own file → `derive` → `default` → `nothing`.
"""
struct Rule
    format::Type
    default::Union{Function, Nothing}
    derive::Union{String, Nothing}
    template::Bool
end

Rule(format::Type = String; default = nothing, derive = nothing, template = false) =
    Rule(format, default, derive, template)

"Lazy path into the built-in recipes directory."
defaultdir(name::AbstractString) = () -> joinpath(DEFAULT_DIR, name)

"Lazy path to an asset shipped by a dependency."
pkgasset(mod::Module, name::AbstractString) = () -> joinpath(pkgdir(mod), name)

# ─────────────────────────────────────────────────────────────────────────────
# The table
# ─────────────────────────────────────────────────────────────────────────────

const TARGETS = (
    "meta" => (
        "icon.svg"   => Rule(IconSource),
        "icon.png"   => Rule(IconSource; derive = "meta/icon.svg", default = pkgasset(IconTools, "assets/icon.png")),
        "startup.jl" => Rule(; default = "startup.jl" |> defaultdir, template = true),
        "msix" => (
            "Assets"                   => Rule(; derive = "meta/icon.png"),
            "AppxManifest.xml"         => Rule(; default = "msix/AppxManifest.xml" |> defaultdir, template = true),
            "resources.pri"            => Rule(; default = pkgasset(MsixPack, "assets/resources.pri")),
            "MSIXAppInstallerData.xml" => Rule(; default = "msix/MSIXAppInstallerData.xml" |> defaultdir, template = true),
            "bootstrap.ps1"            => Rule(; default = pkgasset(MsixPack, "assets/bootstrap.ps1")),
            "certificate.pfx"          => Rule(),
        ),
        "dmg" => (
            "icon.icns"          => Rule(; derive = "meta/icon.png"),
            "Info.plist"         => Rule(; default = "dmg/Info.plist" |> defaultdir, template = true),
            "Entitlements.plist" => Rule(; default = "dmg/Entitlements.plist" |> defaultdir, template = true),
            "DS_Store.toml"      => Rule(DSStoreTOML; default = "dmg/DS_Store.toml" |> defaultdir, template = true),
            "DS_Store"           => Rule(; derive = "meta/dmg/DS_Store.toml"),
            "main.sh"            => Rule(; default = "dmg/main.sh" |> defaultdir, template = true),
            "certificate.pfx"    => Rule(),
        ),
        "snap" => (
            "icon.png"     => Rule(; derive = "meta/icon.png"),
            "snap.yaml"    => Rule(; default = "snap/snap.yaml" |> defaultdir, template = true),
            "main.desktop" => Rule(; default = "snap/main.desktop" |> defaultdir, template = true),
            "configure.sh" => Rule(; template = true),
        ),
        "appimage" => (
            "AppRun.sh" => Rule(; default = "appimage/AppRun.sh" |> defaultdir, template = true),
        ),
    ),
    ".github/workflows/Release.yml" => Rule(; default = "workflows/GitHub.yml" |> defaultdir),
    ".gitlab-ci.yml"                => Rule(; default = "workflows/GitLab.yml" |> defaultdir),
)

# Target names always use "/", also on Windows; joinpath(project, target) accepts that.
function flatten_targets(tree, prefix = "", out = Dict{String, Rule}())
    for (name, node) in tree
        path = isempty(prefix) ? name : "$prefix/$name"
        haskey(out, path) && error("Target $path declared twice")
        node isa Rule ? (out[path] = node) : flatten_targets(node, path, out)
    end
    return out
end

const RULES = flatten_targets(TARGETS)

function rule(target::AbstractString)
    haskey(RULES, target) && return RULES[target]
    error("Unknown target $target. Available targets:\n  " * join(sort!(collect(keys(RULES))), "\n  "))
end

# ─────────────────────────────────────────────────────────────────────────────
# locate / resolve
# ─────────────────────────────────────────────────────────────────────────────

"""
    locate(project, target; skip_own = false)
        -> (; value, origin, from) | nothing

- `value`:  what `resolve` returns: a path `String`, or `IconSource`/`DSStoreTOML`
- `origin`: `:project` or `:default`
- `from`:   the target the file belongs to; differs from `target` when generated

`skip_own` ignores the project's own file for `target` (what `inline` needs).
"""
function locate(project::AbstractString, target::AbstractString; skip_own::Bool = false)
    r = rule(target)

    if !skip_own
        path = joinpath(project, target)
        ispath(path) && return (; value = r.format(path), origin = :project, from = target)
    end

    if !isnothing(r.derive)
        found = locate(project, r.derive)
        isnothing(found) || return found
    end

    isnothing(r.default) && return nothing
    path = r.default()
    ispath(path) || error("Built-in default for $target is missing: $path. This is a packaging bug.")
    return (; value = r.format(path), origin = :default, from = target)
end

"""
    resolve(project, target) -> String | IconSource | DSStoreTOML | nothing

`nothing` only for targets with neither a default nor a resolvable `derive`
(certificates, configure.sh, icon.svg).
"""
function resolve(project::AbstractString, target::AbstractString)
    found = locate(project, target)
    return isnothing(found) ? nothing : found.value
end



function resolve(target::AbstractString)
    
    r = rule(target)
    if isnothing(r.default)
        if !isnothing(r.derive)
            resolve(r.derive)
        else
            error("Can't resolve $target")
        end
    else
        return r.default()
    end
end

resolve(::Nothing, target::AbstractString) = resolve(target)


# "Like `resolve`, but for targets the bundle cannot be built without."
# function require(project::AbstractString, target::AbstractString)
#     value = resolve(project, target)
#     isnothing(value) && error("$target is required: add $(joinpath(project, target))")
#     return value
# end

render(path::AbstractString, parameters) = Mustache.render(Mustache.load(path), parameters)

# ─────────────────────────────────────────────────────────────────────────────
# Use 1: DMG fields are plain paths unless they need conversion
# ─────────────────────────────────────────────────────────────────────────────
#
# struct DMG
#     icon::Union{String, IconSource}            # own .icns, or generated from icon.png/svg
#     info_plist::String                         # template
#     entitlements::String                       # template
#     dsstore::Union{String, DSStoreTOML}        # own DS_Store, or rendered from TOML
#     main_launcher::Union{String, Nothing}      # template
#     ...
# end
#
# DMG(project;
#     icon          = require(project, "meta/dmg/icon.icns"),
#     info_plist    = require(project, "meta/dmg/Info.plist"),
#     entitlements  = require(project, "meta/dmg/Entitlements.plist"),
#     dsstore       = require(project, "meta/dmg/DS_Store"),
#     main_launcher = resolve(project, "meta/dmg/main.sh"), ...)
#
# A user override is now just a path:  DMG(project; info_plist = "my/Info.plist")

dmg_icon(icon::String)     = icon                               # copied as .icns
dmg_icon(icon::IconSource) = DmgPack.IconSource(icon.path)

dmg_dsstore(dsstore::String, parameters)      = dsstore         # copied as .DS_Store
dmg_dsstore(dsstore::DSStoreTOML, parameters) = TOML.parse(render(dsstore.path, parameters))

# ─────────────────────────────────────────────────────────────────────────────
# Use 2: status walks the declared tree
# ─────────────────────────────────────────────────────────────────────────────

"""
    override_status(project, target) -> Bool | String

- `true`   : the project's own file is used
- `false`  : the built-in default is used, or the target is absent
- `String` : the target is generated from this other target, e.g. `"meta/icon.svg"`
"""
function override_status(project::AbstractString, target::AbstractString)
    found = locate(project, target)
    isnothing(found)     && return false
    found.from != target && return found.from
    return found.origin === :project
end

"""
    override_status(project) -> nested tuple shaped like TARGETS

Same shape and leaf values as today's `override_status`, so `print_overrides`
works unchanged (a `String` leaf prints as `[source = …]`).
"""
function override_status(project::AbstractString; tree = TARGETS, prefix = "")
    return Tuple(
        begin
            target = isempty(prefix) ? name : "$prefix/$name"
            node isa Rule ? name => override_status(project, target) :
                            name => override_status(project; tree = node, prefix = target)
        end
        for (name, node) in tree
    )
end

# print_overrides(io::IO, project::AbstractString) =
#     print_overrides(io, override_status(project))

# ─────────────────────────────────────────────────────────────────────────────
# Use 3: inline
# ─────────────────────────────────────────────────────────────────────────────

# How a target's file is produced when it is not a plain copy: it is derived from
# another target, or it has no source at all (certificates). The first argument is
# the resolved value (IconSource, DSStoreTOML, or nothing).
const GENERATORS = Dict{String, Function}(
    "meta/icon.png"             => (src, dest; _...) -> IconTools.save(dest, IconTools.load(src.path)),
    "meta/msix/Assets"          => (src, dest; preferences, _...) -> begin
                                       mkpath(dest)
                                       plate = preferences["msix"]["store_icon_plate"]
                                       for (file, icon) in IconTools.tomsix(IconTools.load(src.path); store_icon_plate = plate)
                                           IconTools.save(joinpath(dest, file), icon)
                                       end
                                   end,
    "meta/msix/certificate.pfx" => (_, dest; preferences, _...) ->
                                       MsixPack.generate_signer(; path = dest, publisher = preferences["msix"]["publisher"]),
    "meta/dmg/icon.icns"        => (src, dest; _...) -> write(dest, IconTools.toicns(IconTools.load(src.path))),
    "meta/dmg/DS_Store"         => (src, dest; parameters, _...) ->
                                       DmgPack.materialize_dsstore(dmg_dsstore(src, parameters), dest),
    "meta/dmg/certificate.pfx"  => (_, dest; _...) -> DmgPack.generate_signer(; path = dest),
    "meta/snap/icon.png"        => (src, dest; _...) -> IconTools.save(dest, IconTools.toicon(IconTools.load(src.path), 512)),
)



# need to make a pure function here
function get_template_parameters(project_dir, target; defines = [])

    preferences = load_preferences(project_dir; defines)["AppBundler"]

    startswith(target, "meta/msix/")     && return MSIX(project_dir; preferences).parameters 
    startswith(target, "meta/snap/")     && return Snap(project_dir; preferences).parameters
    startswith(target, "meta/dmg/")      && return DMG(project_dir; preferences).parameters
    startswith(target, "meta/appimage/") && return AppImage(project_dir; preferences).parameters
    return get_bundle_parameters(preferences)
end


"""
    inline(project_dir, target; force = false, render = false, defines = [], verbose = false,
           destination = joinpath(project_dir, target)) -> destination

Write `target` into the project so it can be customised, taking what the build
would otherwise use:

- a file of the target's own (its default) is copied; with `render = true` a
  template is rendered with the project's template parameters instead;
- a target generated from another one (icons, `DS_Store`) or from nothing
  (certificates) is produced with its generator.

`defines` override `LocalPreferences.toml` entries for rendering and generation.
For `"LocalPreferences.toml"` itself, `defines` are written into the file.
Errors if `destination` exists, unless `force = true`.
"""
function inline(project_dir, target; force = false, render = false, defines = Pair[], verbose = false,
                destination = joinpath(project_dir, target))

    defines = ArgTools.coerce(defines, LOCAL_PREFERENCES_SCHEMA)

    if target == "LocalPreferences.toml"
        PrefTools.inline_preferences(destination, defines; section = "AppBundler")
        return destination
    end

    # Work out what to write before touching the file system
    r       = rule(target)                                   # unknown target → error listing all targets
    found   = locate(project_dir, target; skip_own = true)   # what the build uses without our own file
    derived = isnothing(found) || found.from != target
    generator = get(GENERATORS, target, nothing)

    if derived && isnothing(generator)
        error("$target has no default to inline")            # e.g. meta/snap/configure.sh
    end
    if render && !derived && !r.template
        @warn "$target is not a template; copying it unchanged"
    end

    # Parameters are needed to render a template, or to generate from one (DS_Store.toml)
    needs_parameters = derived ? !isnothing(found) && rule(found.from).template : render && r.template
    preferences = load_preferences(project_dir; defines)["AppBundler"]
    parameters  = needs_parameters ? get_template_parameters(project_dir, target; defines) : nothing

    if verbose && !isnothing(parameters)
        println("-------------- TEMPLATE PARAMETERS -----------")
        for key in sort!(collect(keys(parameters)))
            println("$key = $(repr(parameters[key]))")
        end
        println("----------------------------------------------")
    end

    if ispath(destination)
        force || error("$destination already exists; pass `force = true` to overwrite it")
        rm(destination; recursive = true)
    end
    mkpath(dirname(destination))

    if derived
        return generator(isnothing(found) ? nothing : found.value, destination; parameters, preferences)
    elseif render && r.template
        install(_path(found.value), destination; parameters)
    else
        cp(_path(found.value), destination)
    end

    #return destination
    return nothing
end



# function inline(project::AbstractString, target::AbstractString; defines = [], 
#                 force::Bool = false, render::Bool = false,
#                 parameters = nothing, preferences = nothing)

#     if target == "LocalPreferences.toml" 
#         defines = ArgTools.coerce(defines, LOCAL_PREFERENCES_SCHEMA)
#         PrefTools.inline_preferences(destination, defines; section = "AppBundler")
#         return
#     end 

#     r     = rule(target)                                      # unknown target → error, nothing deleted
#     found = locate(project, target; skip_own = true)
#     gen   = get(GENERATORS, target, nothing)
#     dest  = joinpath(project, target)

#     derived = isnothing(found) || found.from != target
#     derived && isnothing(gen) && error("$target has no default to inline")

#     if ispath(dest)
#         force || error("$dest already exists; pass `force = true` to overwrite it")
#         rm(dest; recursive = true)
#     end
#     mkpath(dirname(dest))

#     if derived
#         gen(isnothing(found) ? nothing : found.value, dest; parameters, preferences)
#     elseif render && r.template
#         write(dest, AppBundler.render(found.value, parameters))   # qualified: the `render` keyword shadows it
#     else
#         cp(_path(found.value), dest)
#     end
#     return dest
# end

# ─────────────────────────────────────────────────────────────────────────────
# Tests that keep the table honest
# ─────────────────────────────────────────────────────────────────────────────
#
# @testset "targets" begin
#     for (target, r) in RULES
#         if !isnothing(r.derive)
#             @test haskey(RULES, r.derive)          # full target name
#             @test haskey(GENERATORS, target)       # inline can produce it
#         end
#         isnothing(r.default) || @test ispath(r.default())
#     end
#     # derive chains terminate
#     for target in keys(RULES)
#         seen = Set{String}(); t = target
#         while !isnothing(RULES[t].derive)
#             @test t ∉ seen; push!(seen, t); t = RULES[t].derive
#         end
#     end
#     # empty project: icon.icns comes from the IconTools png
#     empty = mktempdir()
#     @test resolve(empty, "meta/dmg/icon.icns") isa IconSource
#     @test locate(empty, "meta/dmg/icon.icns").from == "meta/icon.png"
#     @test resolve(empty, "meta/dmg/Info.plist") isa String
# end
