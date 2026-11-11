# Argument parsing, tested one layer at a time.
#
#   Knobs.normalize_args     argv tokens -> option => value pairs.  No schema.
#   Knobs.parse_options      argv -> ([option => value], defines).  No schema.
#   Knobs.coerce             defines -> ordered key => typed value pairs.  Schema-driven.

using Knobs
using Knobs: normalize_args
using Test

"""A flat schema for testing the parser on its own."""
const SCHEMA = Dict{String, Any}(
    "name"                => String,
    "bundler"             => ("juliaimg", "juliac"),
    "selfsign"            => Bool,
    "juliaimg.sysimg"     => Vector{String},
    "juliaimg.precompile" => Bool,
)

"""The -D preferences in `args`, coerced against `SCHEMA` into ordered `key => value` pairs."""
function parse_defines(args)
    _, defines = Knobs.parse_options(args)
    return Knobs.coerce(defines, SCHEMA)
end

"""The message an invocation fails with, or `""` if it succeeds."""
function message_of(f)
    try
        f()
        return ""
    catch e
        return sprint(showerror, e)
    end
end


### Layer 1: pairing tokens. No schema reaches this function.

@testset "normalize_args" begin

    @testset "pairing" begin
        # Attached and detached forms are equivalent; only the first '=' splits.
        @test normalize_args(["--password", "hunter2"]) == ["--password" => "hunter2"]
        @test normalize_args(["--password=hunter2"]) == ["--password" => "hunter2"]
        @test normalize_args(["--password=foo=bar"]) == ["--password" => "foo=bar"]
        @test normalize_args(["-Dbundler=juliaimg"]) == ["-D" => "bundler=juliaimg"]
        @test normalize_args(["-D", "bundler=juliaimg"]) == ["-D" => "bundler=juliaimg"]
        @test normalize_args(["--selfsign", "--force"]) ==
              ["--selfsign" => nothing, "--force" => nothing]
    end

    @testset "an option is never adopted as a value, a non-option always is" begin
        @test normalize_args(["--password", "--selfsign"]) ==
              ["--password" => nothing, "--selfsign" => nothing]
        @test normalize_args(["--password", "-secret"]) == ["--password" => "-secret"]
        # Ambiguity the rule buys: a boolean option adopts a following
        # positional. Caught downstream by the caller's arity check.
        @test normalize_args(["--selfsign", "build"]) == ["--selfsign" => "build"]
        @test normalize_args(["build", ".", "--selfsign"]) ==
              ["build" => nothing, "." => nothing, "--selfsign" => nothing]
    end

    @testset "a value is one shell word, taken verbatim" begin
        # Brackets, commas and braces are content here; only coercion reads them.
        @test normalize_args(["-Dkey={a, b}"]) == ["-D" => "key={a, b}"]
        # No pass reaches across a shell split, so an open bracket cannot swallow
        # the option after it, and an attached value truncates at the split.
        @test normalize_args(["--filter", "key=[a", "--selfsign]"]) ==
              ["--filter" => "key=[a", "--selfsign]" => nothing]
        @test normalize_args(["--target-name=My", "App"]) ==
              ["--target-name" => "My", "App" => nothing]
        # The input array is never modified.
        let raw = ["-Dsysimg=[a,b]", "--force"], before = copy(raw)
            normalize_args(raw)
            @test raw == before
        end
    end

    @testset "one layer of outer quotes comes off" begin
        @test normalize_args(["--description=\"Tool for X, Y,\""]) ==
              ["--description" => "Tool for X, Y,"]
        @test normalize_args(["--password", "\"a=b,\""]) == ["--password" => "a=b,"]
        @test normalize_args(["--password=''x''"]) == ["--password" => "'x'"]
        # A single quote inside a word is an apostrophe, never a grouping quote.
        @test normalize_args(["--target-name=Bob's Tool"]) == ["--target-name" => "Bob's Tool"]
        # The -D payload keeps its quotes; they come off per element, later.
        @test normalize_args(["-Dbundler=\"juliaimg\""]) == ["-D" => "bundler=\"juliaimg\""]
    end

    @testset "empty and edge tokens" begin
        @test normalize_args(String[]) == []
        # An attached empty value is "" rather than nothing, so a `require`-style
        # check accepts it. Legitimate for -D (empty list); questionable for
        # path-like flags, where it reaches mkpath("").
        @test normalize_args(["--build-dir="]) == ["--build-dir" => ""]
        @test normalize_args(["-Dsysimg="]) == ["-D" => "sysimg="]
    end
end


### Layer 2: coercing -D payloads against the schema.

@testset "preferences" begin

    @testset "parse_options needs no schema" begin
        # The pairing half runs before any preference set is chosen.
        options, defines = Knobs.parse_options(["build", ".", "--force",
                                                   "-Dbundler=juliaimg", "-Dselfsign"])
        @test options == ["build" => nothing, "." => nothing, "--force" => nothing]
        @test defines == ["bundler" => "juliaimg", "selfsign" => nothing]
    end

    @testset "dotted keys pass through whole, and the schema is flat" begin
        _, defines = Knobs.parse_options(["-Djuliaimg.sysimg=a", "-D", "juliaimg.precompile=false"])
        @test defines == ["juliaimg.sysimg" => "a", "juliaimg.precompile" => "false"]

        @test parse_defines(["-Djuliaimg.sysimg=a", "-D", "juliaimg.precompile=false"]) ==
              ["juliaimg.sysimg" => ["a"], "juliaimg.precompile" => false]
        # Only whole keys exist: a prefix is not a table, a longer path is not a key.
        @test_throws ErrorException parse_defines(["-Djuliaimg=a"])
        @test_throws ErrorException parse_defines(["-Djuliaimg.sysimg.x=a"])
    end

    @testset "strings are never type-guessed" begin
        @test parse_defines(["-Dname=2026"]) == ["name" => "2026"]
        @test parse_defines(["-Dname=true"]) == ["name" => "true"]
        @test parse_defines(["-Dname="]) == ["name" => ""]
        @test parse_defines(["-Dname=a=b"]) == ["name" => "a=b"]
        @test parse_defines(["-Dname=\"sdsd,sds\""]) == ["name" => "sdsd,sds"]
        # An unterminated quote is content in a scalar; only lists scan.
        @test parse_defines(["-Dname=\"juliaimg"]) == ["name" => "\"juliaimg"]
    end

    @testset "allowed values" begin
        @test parse_defines(["-Dbundler=juliac"]) == ["bundler" => "juliac"]
        @test parse_defines(["-Dbundler=\"juliaimg\""]) == ["bundler" => "juliaimg"]
        msg = message_of(() -> parse_defines(["-Dbundler=2026"]))
        @test occursin("preference 'bundler' expects one of 'juliaimg' or 'juliac'", msg)
    end

    @testset "booleans" begin
        @test parse_defines(["-Dselfsign=true"]) == ["selfsign" => true]
        @test parse_defines(["-Dselfsign=\"false\""]) == ["selfsign" => false]
        @test parse_defines(["-Dselfsign"]) == ["selfsign" => true]         # bare key, Bool only
        @test parse_defines(["-D", "selfsign"]) == ["selfsign" => true]     # detached bare bool
        @test_throws Exception parse_defines(["-Dselfsign=yes"])
        @test_throws Exception parse_defines(["-Dbundler"])                 # bare key, not a Bool
    end

    @testset "all list spellings converge" begin
        for raw in ("-Djuliaimg.sysimg=[\"QMLApp\",\"AppEnv\"]",
                    "-Djuliaimg.sysimg=[QMLApp,AppEnv]",
                    "-Djuliaimg.sysimg=QMLApp,AppEnv",
                    "-Djuliaimg.sysimg=[QMLApp, AppEnv]")   # one token: quoted by the shell
            @test parse_defines([raw]) == ["juliaimg.sysimg" => ["QMLApp", "AppEnv"]]
        end
        # A bare scalar promotes to a one-element list; a wholly quoted payload
        # is one element, commas included.
        @test parse_defines(["-Djuliaimg.sysimg=QMLApp"]) == ["juliaimg.sysimg" => ["QMLApp"]]
        @test parse_defines(["-Djuliaimg.sysimg=\"sdsd,sds\""]) == ["juliaimg.sysimg" => ["sdsd,sds"]]
        for raw in ("-Djuliaimg.sysimg=", "-Djuliaimg.sysimg=[]")
            @test parse_defines([raw]) == ["juliaimg.sysimg" => String[]]
        end
    end

    @testset "malformed lists abort the whole invocation" begin
        # A trailing comma inside brackets is conventional and ignored.
        @test parse_defines(["-Djuliaimg.sysimg=[a,b,]"]) == ["juliaimg.sysimg" => ["a", "b"]]
        @test_throws ErrorException parse_defines(["-Djuliaimg.sysimg=[,a]"])
        # Unterminated: must not silently swallow the following option.
        @test_throws Exception parse_defines(["-Djuliaimg.sysimg=[QMLApp,", "--selfsign"])
        @test_throws ErrorException parse_defines(["-Djuliaimg.sysimg=a,", "--selfsign"])
        # A quoted bracket is content, not an open delimiter.
        @test parse_defines(["-Dname=\"[sdfsdffsdf\"", "--force"]) == ["name" => "[sdfsdffsdf"]
    end

    @testset "repeats resolve per the schema" begin
        SYS = "juliaimg.sysimg"
        # Scalars: last value wins, in the position of the first occurrence.
        @test parse_defines(["-Dname=a", "-Dselfsign", "-Dname=b"]) ==
              ["name" => "b", "selfsign" => true]
        @test parse_defines(["-Dselfsign=true", "-Dselfsign=false"]) == ["selfsign" => false]
        @test parse_defines(["-Dbundler=juliaimg", "-Dbundler=juliac"]) == ["bundler" => "juliac"]
        # Lists: a bare value appends, however it is spelled.
        @test parse_defines(["-D$SYS=a", "-D$SYS=b"]) == [SYS => ["a", "b"]]
        @test parse_defines(["-D$SYS=a", "-D$SYS=b,c"]) == [SYS => ["a", "b", "c"]]
        @test parse_defines(["-D$SYS=x", "-D$SYS=\"a,b\""]) == [SYS => ["x", "a,b"]]
        # A bracketed value resets, and appending resumes after it.
        @test parse_defines(["-D$SYS=a", "-D$SYS=[b]"]) == [SYS => ["b"]]
        @test parse_defines(["-D$SYS=a", "-D$SYS=[]"]) == [SYS => String[]]
        @test parse_defines(["-D$SYS=a", "-D$SYS=[b]", "-D$SYS=c"]) == [SYS => ["b", "c"]]
        # A wholly quoted bracketed payload is still a reset.
        @test parse_defines(["-D$SYS=a", "-D$SYS=\"[b, c]\""]) == [SYS => ["b", "c"]]
        # Every occurrence is coerced, even one a later value would override.
        @test_throws ErrorException parse_defines(["-Dselfsign=yes", "-Dselfsign=true"])
        @test occursin("selfsign", message_of(() -> parse_defines(["-Dselfsign=yes", "-Dselfsign=true"])))
    end

    @testset "unknown keys abort rather than build wrong" begin
        @test_throws Exception parse_defines(["-Dbundlr=juliaimg"])
        @test occursin("bundler", message_of(() -> parse_defines(["-Dbundlr=juliaimg"])))
        # An empty key is unknown like any other.
        @test_throws Exception parse_defines(["-D="])
        @test_throws Exception parse_defines(["-D", "=value"])
    end
end


