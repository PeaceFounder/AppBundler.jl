# Argument parsing, tested one layer at a time.
#
#   ArgTools.parse_options      argv -> ([option => value], defines).  No schema.
#   ArgTools.coerce             defines -> ordered key => typed value pairs.  Schema-driven.
#   AppBundler.parse_build_args       wraps both and builds the config.
#
# The invocation that motivated the parser, now writable without escapes:
#
#   appbundler build . --build-dir=build --selfsign \
#       -Dbundler=juliaimg -Djuliaimg.selective_assets=true -Djuliaimg.sysimg=[QMLApp]

using AppBundler

using Test

using AppBundler: parse_build_args, ArgTools
using AppBundler.ArgTools: normalize_args

# Layer 3 helpers: the config and the preferences from AppBundler's own parser.
config_of(args) = parse_build_args(String.(args))[1]
prefs_of(args) = parse_build_args(String.(args))[2]

"""A flat schema for testing ArgTools on its own, independent of AppBundler's."""
const SCHEMA = Dict{String, Any}(
    "name"                => String,
    "bundler"             => ("juliaimg", "juliac"),
    "selfsign"            => Bool,
    "juliaimg.sysimg"     => Vector{String},
    "juliaimg.precompile" => Bool,
)

"""The -D preferences in `args`, coerced against `SCHEMA` into ordered `key => value` pairs."""
function parse_defines(args)
    _, defines = ArgTools.parse_options(args)
    return ArgTools.coerce(defines, SCHEMA)
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
        options, defines = ArgTools.parse_options(["build", ".", "--force",
                                                   "-Dbundler=juliaimg", "-Dselfsign"])
        @test options == ["build" => nothing, "." => nothing, "--force" => nothing]
        @test defines == ["bundler" => "juliaimg", "selfsign" => nothing]
    end

    @testset "dotted keys pass through whole, and the schema is flat" begin
        _, defines = ArgTools.parse_options(["-Djuliaimg.sysimg=a", "-D", "juliaimg.precompile=false"])
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


### Layer 3: flags, defaults and the AppBundler config they build.
#
# Preferences are compared as a Dict here: the order in which flag-derived and
# -D preferences interleave is parse_build_args' business, not what these test.

@testset "parse_build_args" begin

    @testset "the motivating invocation, whole" begin
        # Every token of the documented command line, in one call: an attached
        # path flag, a bare flag, and three -D forms. Run inside a temp dir
        # because --build-dir is created as a side effect.
        mktempdir() do dir
            cd(dir) do
                config, prefs = parse_build_args(["--build-dir=build",
                                                  "--selfsign",
                                                  "-Dbundler=juliaimg",
                                                  "-Djuliaimg.selective_assets=true",
                                                  "-Djuliaimg.sysimg=[QMLApp]"])
                @test basename(config[:build_dir]) == "build"
                # Untouched flags keep their defaults alongside the ones given.
                @test config[:target_name] === nothing
                @test config[:password] === nothing
                @test config[:target_arch] === Sys.ARCH
                @test Dict(prefs) == Dict("selfsign" => true,
                                          "bundler" => "juliaimg",
                                          "juliaimg.selective_assets" => true,
                                          "juliaimg.sysimg" => ["QMLApp"])
            end
        end
    end

    @testset "the motivating invocation, escaped form still works" begin
        prefs = prefs_of(["-Dbundler=\"juliaimg\"",
                          "-Djuliaimg.selective_assets=true",
                          "-Djuliaimg.sysimg=[\"QMLApp\"]"])
        @test prefs == ["bundler" => "juliaimg",
                        "juliaimg.selective_assets" => true,
                        "juliaimg.sysimg" => ["QMLApp"]]
    end

    @testset "defaults with no arguments" begin
        config, prefs = parse_build_args(String[])
        @test isdir(config[:build_dir])
        @test config[:target_name] === nothing
        @test config[:password] === nothing
        @test config[:target_arch] === Sys.ARCH
        @test isempty(prefs)
    end

    @testset "flags carry their values into the config" begin
        config, prefs = parse_build_args(["--target-name", "My App",
                                          "--target-arch", "aarch64",
                                          "--target-bundle", "dmg",
                                          "--password=  hunter2  ",
                                          "--force",
                                          "-Djuliaimg.sysimg=[QMLApp, AppEnv]"])
        @test config[:target_name] == "My App"
        @test config[:target_arch] === :aarch64
        @test config[:target_bundle] === :dmg
        @test config[:password] == "hunter2"          # stripped, attached or not
        @test Dict(prefs) == Dict("overwrite_target" => true,
                                  "juliaimg.sysimg" => ["QMLApp", "AppEnv"])
        # A repeated flag takes the last value, as -D does for scalar preferences.
        @test config_of(["--target-arch", "x86_64",
                         "--target-arch", "aarch64"])[:target_arch] === :aarch64
    end

    @testset "flag-set preferences" begin
        @test prefs_of(["--skipsign"]) == ["skipsign" => true]
        # --debug sets windowed=false, compress=false and selfsign=true.
        @test Dict(prefs_of(["--debug"])) ==
              Dict("windowed" => false, "compress" => false, "selfsign" => true)
    end

    @testset "-D overrides win over flag-set preferences" begin
        @test prefs_of(["--selfsign", "-Dselfsign=false"]) == ["selfsign" => false]
        # The override wins whichever order they appear; the rest of --debug stays.
        @test Dict(prefs_of(["-Dcompress=true", "--debug"])) ==
              Dict("windowed" => false, "compress" => true, "selfsign" => true)
        @test Dict(prefs_of(["--debug", "-Dcompress=true"])) ==
              Dict("windowed" => false, "compress" => true, "selfsign" => true)

    end

    @testset "a value holding brackets does not disturb its neighbours" begin
        config, prefs = parse_build_args(["--password", "ab[cd", "--selfsign"])
        @test config[:password] == "ab[cd"
        @test prefs == ["selfsign" => true]
    end

    @testset "missing values report properly" begin
        for flag in ("--target-name", "--password", "--target-arch",
                     "--target-bundle", "--build-dir", "-D")
            @testset "$flag" begin
                @test_throws ErrorException parse_build_args([flag])
                @test_throws ErrorException parse_build_args([flag, "--selfsign"])
            end
        end
    end

    @testset "unknown flags warn but do not abort" begin
        @test_logs (:warn,) match_mode = :any begin
            @test prefs_of(["--nonsense", "-Dbundler=juliaimg"]) == ["bundler" => "juliaimg"]
        end
    end
end
