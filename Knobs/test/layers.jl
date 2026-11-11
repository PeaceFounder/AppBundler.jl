# Layers, rules and resolution: everything after the command line is split.

using Knobs
using Knobs: Rule
using Test

"""The message `f` fails with, or `""` if it succeeds."""
function message_of(f)
    try
        f()
        return ""
    catch e
        return sprint(showerror, e)
    end
end

struct HexColor end

function Knobs.coerce(value, ::HexColor)
    value isa AbstractString && occursin(r"^#[0-9A-Fa-f]{6}$", value) && return String(value)
    throw(Knobs.CoercionError("expects a hex colour like #f3f3f3, got $(repr(value))"))
end

const SCHEMA = Dict{String, Any}(
    "app_name"     => String,
    "app_exe"      => String,
    "module_name"  => Union{String, Nothing},
    "compress"     => Bool,
    "jobs"         => Int,
    "ratio"        => Float64,
    "backend"      => ("xorriso", "hfsplus"),
    "colour"       => HexColor(),
    "sysimg"       => Vector{String},
    "dmg.command"  => Vector{String},
)

entry(entries, key) = only(filter(e -> e.key == key, entries))

base(; kwargs...) = Pair{String, Any}[
    "app_name" => "MyApp", "app_exe" => "myapp", "compress" => true, "jobs" => 1,
    "ratio" => 0.5, "backend" => "xorriso", "colour" => "#f3f3f3", "sysimg" => String[],
    "dmg.command" => ["bin/myapp"], kwargs...]


@testset "coerce(value, spec)" begin

    @testset "text and typed values meet the same spec" begin
        @test Knobs.coerce("true", Bool) === true
        @test Knobs.coerce(true, Bool) === true
        @test Knobs.coerce("3", Int) === 3
        @test Knobs.coerce(3, Int) === 3
        @test Knobs.coerce(1, Float64) === 1.0             # TOML writes 1 for a float field
        @test Knobs.coerce("a,b", Vector{String}) == ["a", "b"]
        @test Knobs.coerce(Any["a", "b"], Vector{String}) == ["a", "b"]
        @test Knobs.coerce(Any[], Vector{String}) == String[]   # TOML parses [] to Vector{Any}
        @test Knobs.coerce("hfsplus", ("xorriso", "hfsplus")) == "hfsplus"
        @test Knobs.coerce("aarch64", Symbol) === :aarch64
    end

    @testset "wrong typed values are rejected" begin
        @test_throws Knobs.CoercionError Knobs.coerce(1, Bool)
        @test_throws Knobs.CoercionError Knobs.coerce(true, Float64)
        @test_throws Knobs.CoercionError Knobs.coerce("x", Int)
        @test_throws Knobs.CoercionError Knobs.coerce(Any[1], Vector{String})
        @test_throws Knobs.CoercionError Knobs.coerce("lzma", ("xorriso", "hfsplus"))
    end

    @testset "optional specs" begin
        @test Knobs.coerce(nothing, Union{String, Nothing}) === nothing
        @test Knobs.coerce("x", Union{String, Nothing}) == "x"
        @test_throws Knobs.CoercionError Knobs.coerce(1, Union{String, Nothing})
    end

    @testset "a custom spec needs one method" begin
        @test Knobs.coerce("#abcdef", HexColor()) == "#abcdef"
        @test_throws Knobs.CoercionError Knobs.coerce("blue", HexColor())
        msg = message_of(() -> Knobs.coerce(Pair{String, Any}["colour" => "blue"], SCHEMA))
        @test occursin("preference 'colour' expects a hex colour", msg)
    end

    @testset "a typed vector resets a list, bare text appends" begin
        pairs = Pair{String, Any}["sysimg" => "a", "sysimg" => ["b"], "sysimg" => "c"]
        @test Knobs.coerce(pairs, SCHEMA) == ["sysimg" => ["b", "c"]]
    end

    @testset "no method ambiguities" begin
        @test isempty(Test.detect_ambiguities(Knobs))
    end
end


@testset "value and flag" begin
    @test Knobs.value("--build-dir", "out") == "out"
    @test Knobs.value("--jobs", "4", Int) == 4
    @test Knobs.value("--arch", "aarch64", Symbol) === :aarch64
    @test occursin("--build-dir requires a value", message_of(() -> Knobs.value("--build-dir", nothing)))
    @test occursin("--jobs expects an integer, got 'many'", message_of(() -> Knobs.value("--jobs", "many", Int)))
    @test Knobs.flag("--force", nothing)
    @test occursin("--force does not take a value", message_of(() -> Knobs.flag("--force", "yes")))
end


@testset "flatten and nest" begin
    table = Dict("app_name" => "X", "dmg" => Dict("backend" => "xorriso", "xorriso" => Dict("hfsplus" => false)))
    flat = Knobs.flatten(table)
    @test flat == ["app_name" => "X", "dmg.backend" => "xorriso", "dmg.xorriso.hfsplus" => false]
    @test Knobs.nest(flat) == table
    @test Knobs.nest(Dict(flat)) == table
    @test_throws ErrorException Knobs.nest(["a" => 1, "a.b" => 2])
    @test_throws ErrorException Knobs.nest(["a.b" => 2, "a" => 1])
end


@testset "resolve" begin

    @testset "later layers win" begin
        layers = ["defaults" => base(), "project" => ["backend" => "hfsplus", "jobs" => 2],
                  "command line" => Pair{String, Any}["jobs" => "8"]]
        prefs = Knobs.resolve(SCHEMA, layers)
        @test prefs["backend"] == "hfsplus"
        @test prefs["jobs"] == 8
        @test prefs["app_name"] == "MyApp"
        @test !haskey(prefs, "module_name")          # optional and unset
    end

    @testset "unlabelled layers" begin
        prefs = Knobs.resolve(SCHEMA, [base(), ["jobs" => 3]])
        @test prefs["jobs"] == 3
        entries = Knobs.status(SCHEMA, [base(), ["jobs" => 3]])
        @test entry(entries, "jobs").origin == 2
    end

    @testset "every problem is reported at once, with its layer" begin
        layers = ["defaults" => base(), "project" => ["backend" => "hfs", "compres" => false]]
        msg = message_of(() -> Knobs.resolve(SCHEMA, layers))
        @test occursin("backend: project: expects one of 'xorriso' or 'hfsplus', got 'hfs'", msg)
        @test occursin("compres: project: unknown preference; did you mean 'compress'?", msg)
    end

    @testset "required keys must be set" begin
        msg = message_of(() -> Knobs.resolve(SCHEMA, [["app_name" => "X"]]))
        @test occursin("compress: is not set", msg)
    end
end


@testset "rules" begin

    @testset "computed from other keys, plain values win" begin
        inferred = ["app_exe" => Rule(lowercase, "app_name")]
        prefs = Knobs.resolve(SCHEMA, ["inferred" => inferred, "defaults" => base()[[1; 3:end]]])
        @test prefs["app_exe"] == "myapp"

        prefs = Knobs.resolve(SCHEMA, ["inferred" => inferred, "defaults" => base(), "cli" => ["app_exe" => "custom"]])
        @test prefs["app_exe"] == "custom"
    end

    @testset "inputs come from the final stack, rules from any layer" begin
        inferred = ["app_exe" => Rule(lowercase, "app_name")]
        layers = ["inferred" => inferred, "defaults" => base()[[1; 3:end]],
                  "cli" => Pair{String, Any}["app_name" => "FromCLI"]]
        @test Knobs.resolve(SCHEMA, layers)["app_exe"] == "fromcli"

        layers = ["defaults" => base(), "cli" => ["jobs" => Rule(() -> 16)]]
        @test Knobs.resolve(SCHEMA, layers)["jobs"] == 16
    end

    @testset "rules chain lazily, and status names their inputs" begin
        inferred = ["app_exe"  => Rule(lowercase, "app_name"),
                    "app_name" => Rule(() -> "Chained")]
        entries = Knobs.status(SCHEMA, ["inferred" => inferred, "defaults" => base()[3:end]])
        @test entry(entries, "app_exe").value == "chained"
        @test entry(entries, "app_exe").from == ("app_name",)
        @test entry(entries, "app_exe").origin == "inferred"
        @test entry(entries, "app_name").from == ()
        @test isnothing(entry(entries, "app_exe").problem)
    end

    @testset "alternatives: skip on nothing, decline with nothing" begin
        command = ["module_name" => Rule(n -> n == "Mod" ? "Mod" : nothing, "app_name"),
                   "dmg.command" => Rule(m -> ["bin/julia", "-m", m], "module_name"),
                   "dmg.command" => Rule(exe -> ["bin/$exe"], "app_exe")]
        defaults = filter(p -> first(p) ∉ ("app_name", "dmg.command"), base())

        prefs = Knobs.resolve(SCHEMA, [command, defaults, ["app_name" => "Mod"]])
        @test prefs["dmg.command"] == ["bin/julia", "-m", "Mod"]

        entries = Knobs.status(SCHEMA, [command, defaults, ["app_name" => "Other"]])
        @test entry(entries, "dmg.command").value == ["bin/myapp"]
        @test entry(entries, "dmg.command").from == ("app_exe",)
        @test isnothing(entry(entries, "module_name").value)         # declined, optional
        @test isnothing(entry(entries, "module_name").problem)
    end

    @testset "a failed input is reported, not skipped" begin
        command = ["module_name" => Rule(() -> error("src/MyApp.jl not found")),
                   "dmg.command" => Rule(m -> ["bin/julia", "-m", m], "module_name"),
                   "dmg.command" => Rule(exe -> ["bin/$exe"], "app_exe")]
        defaults = filter(p -> first(p) != "dmg.command", base())
        entries = Knobs.status(SCHEMA, [command, defaults])
        @test occursin("could not be inferred: src/MyApp.jl not found", entry(entries, "module_name").problem)
        @test occursin("needs module_name: could not be inferred", entry(entries, "dmg.command").problem)
        @test isnothing(entry(entries, "dmg.command").value)
        # The failure stays local
        @test isnothing(entry(entries, "app_exe").problem)
    end

    @testset "a bad value used as input fails its dependents" begin
        inferred = ["app_exe" => Rule(lowercase, "app_name")]
        defaults = filter(p -> first(p) != "app_exe", base())
        entries = Knobs.status(SCHEMA, ["inferred" => inferred, "defaults" => defaults, "project" => ["app_name" => false]])
        @test entry(entries, "app_name").value == false
        @test occursin("project: expects a string", entry(entries, "app_name").problem)
        @test occursin("needs app_name: project: expects a string", entry(entries, "app_exe").problem)
    end

    @testset "required key whose rules all decline" begin
        entries = Knobs.status(SCHEMA, [["app_exe" => Rule(() -> nothing)], base()[[1; 3:end]]])
        @test entry(entries, "app_exe").problem == "could not be inferred"
    end

    @testset "results are coerced" begin
        entries = Knobs.status(SCHEMA, [base(), ["jobs" => Rule(() -> "many")]])
        @test occursin("rule result expects an integer", entry(entries, "jobs").problem)
        @test Knobs.resolve(SCHEMA, [base(), ["sysimg" => Rule(() -> Any["A"])]])["sysimg"] == ["A"]
    end

    @testset "cycles are reported" begin
        cyclic = ["app_name" => Rule(identity, "app_exe"),
                  "app_exe"  => Rule(identity, "app_name")]
        entries = Knobs.status(SCHEMA, [base()[3:end], cyclic])
        @test occursin("dependency cycle", entry(entries, "app_name").problem)
        @test occursin("dependency cycle", entry(entries, "app_exe").problem)
    end

    @testset "an unknown input" begin
        entries = Knobs.status(SCHEMA, [base(), ["app_exe" => Rule(identity, "nope")]])
        @test occursin("'nope' is not in the schema", entry(entries, "app_exe").problem)
    end
end


@testset "status" begin
    layers = ["defaults" => base(), "project" => ["backend" => "hfsplus", "unknown_key" => 1]]
    entries = Knobs.status(SCHEMA, layers)

    @test issorted(entries; by = e -> e.key)
    @test allunique(e.key for e in entries)
    @test entry(entries, "backend").origin == "project"
    @test entry(entries, "compress").origin == "defaults"
    @test entry(entries, "unknown_key").value == 1
    @test occursin("unknown preference", entry(entries, "unknown_key").problem)
    @test isnothing(entry(entries, "module_name").origin)
end


@testset "print_status" begin
    inferred = ["app_exe" => Rule(lowercase, "app_name")]
    defaults = filter(p -> first(p) ∉ ("app_exe", "backend"), base())
    layers = ["inferred" => inferred, "defaults" => defaults,
              "project" => ["backend" => "hfs"], "command line" => Pair{String, Any}["jobs" => "8"]]

    io = IOBuffer()
    Knobs.print_status(io, SCHEMA, layers)
    out = String(take!(io))

    # Highest-precedence layer first, then down to the inferred values, then unset keys
    headers = ["command line", "project", "defaults", "inferred", "unset"]
    positions = [findfirst("\n" * h * "\n", "\n" * out) for h in headers]
    @test all(!isnothing, positions)
    @test issorted(first.(positions))

    @test occursin(r"jobs\s+= 8", out)
    @test occursin(r"app_exe\s+= \"myapp\"  \(from app_name\)", out)
    @test occursin(r"! backend\s+= \"hfs\"", out)
    @test occursin("project: expects one of 'xorriso' or 'hfsplus', got 'hfs'", out)
    @test occursin(r"module_name\s+= nothing", out)

    # Entries alone print in order of first appearance; unlabelled layers are named by position
    io = IOBuffer()
    Knobs.print_status(io, Knobs.status(SCHEMA, [base()]))
    @test occursin("layer 1\n", String(take!(io)))
end
