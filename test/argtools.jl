# Argument parsing, tested one layer at a time.
#
#   ArgTools.parse_options      argv -> ([option => value], defines).  No schema.
#   ArgTools.parse_preferences  defines -> typed preferences.  Schema-driven.
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

config_of(argv...) = parse_build_args(String[argv...])[1]
prefs_of(argv...) = parse_build_args(String[argv...])[2]

"""Preferences via ArgTools alone, against an explicit schema."""
function argtools_prefs(argv, schema; kwargs...)
    _, defines = ArgTools.parse_options(argv)
    return ArgTools.parse_preferences(defines, schema; kwargs...)
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

    @testset "dotted keys pass through whole and nest against the schema" begin
        _, defines = ArgTools.parse_options(["-Djuliaimg.sysimg=a", "-D", "juliaimg.precompile=false"])
        @test defines == ["juliaimg.sysimg" => "a", "juliaimg.precompile" => "false"]
        schema = Dict{String, Any}("juliaimg" => Dict{String, Any}("sysimg" => String[], "precompile" => true))
        @test ArgTools.parse_preferences(defines, schema) ==
              Dict("juliaimg" => Dict("sysimg" => ["a"], "precompile" => false))
        @test_throws ErrorException argtools_prefs(["-Djuliaimg=a"], schema)          # a table is not a value
        @test_throws ErrorException argtools_prefs(["-Djuliaimg.sysimg.x=a"], schema) # nor a path through one
    end

    @testset "strings are never type-guessed" begin
        @test prefs_of("-Dbundler=2026")["bundler"] === "2026"
        @test prefs_of("-Dbundler=true")["bundler"] === "true"
        @test prefs_of("-Dbundler=")["bundler"] === ""
        @test prefs_of("-Dbundler=a=b")["bundler"] == "a=b"
        @test prefs_of("-Dbundler=\"sdsd,sds\"")["bundler"] == "sdsd,sds"
        # An unterminated quote is content in a scalar; only lists scan.
        @test prefs_of("-Dbundler=\"juliaimg")["bundler"] == "\"juliaimg"
    end

    @testset "booleans" begin
        @test prefs_of("-Dselfsign=true")["selfsign"] === true
        @test prefs_of("-Dselfsign=\"false\"")["selfsign"] === false
        @test prefs_of("-Dselfsign")["selfsign"] === true   # bare key, Bool only
        @test prefs_of("-D", "selfsign")["selfsign"] === true   # detached bare bool
        @test_throws Exception prefs_of("-Dselfsign=yes")
        @test_throws Exception prefs_of("-Dbundler")        # bare key, not a Bool
    end

    @testset "all list spellings converge" begin
        for raw in ("-Djuliaimg.sysimg=[\"QMLApp\",\"AppEnv\"]",
                    "-Djuliaimg.sysimg=[QMLApp,AppEnv]",
                    "-Djuliaimg.sysimg=QMLApp,AppEnv",
                    "-Djuliaimg.sysimg=[QMLApp, AppEnv]")   # one token: quoted by the shell
            @test prefs_of(raw)["juliaimg"]["sysimg"] == ["QMLApp", "AppEnv"]
        end
        # A bare scalar promotes to a one-element list; a wholly quoted payload
        # is one element, commas included.
        @test prefs_of("-Djuliaimg.sysimg=QMLApp")["juliaimg"]["sysimg"] == ["QMLApp"]
        @test prefs_of("-Djuliaimg.sysimg=\"sdsd,sds\"")["juliaimg"]["sysimg"] == ["sdsd,sds"]
        for raw in ("-Djuliaimg.sysimg=", "-Djuliaimg.sysimg=[]")
            @test isempty(prefs_of(raw)["juliaimg"]["sysimg"])
        end
    end

    @testset "malformed lists abort the whole invocation" begin
        # A trailing comma inside brackets is conventional and ignored.
        @test prefs_of("-Djuliaimg.sysimg=[a,b,]")["juliaimg"]["sysimg"] == ["a", "b"]
        @test_throws ErrorException prefs_of("-Djuliaimg.sysimg=[,a]")
        # Unterminated: must not silently swallow the following option.
        @test_throws Exception prefs_of("-Djuliaimg.sysimg=[QMLApp,", "--selfsign")
        @test_throws ErrorException prefs_of("-Djuliaimg.sysimg=a,", "--selfsign")
        # A quoted bracket is content, not an open delimiter.
        prefs = prefs_of("-Dbundler=\"[sdfsdffsdf\"", "--force")
        @test prefs["bundler"] == "[sdfsdffsdf"
        @test prefs["overwrite_target"] === true
    end

    @testset "a repeated key" begin
        # Scalars take the last value, matching a repeated flag.
        @test prefs_of("-Dbundler=first", "-Dbundler=second")["bundler"] == "second"
        # Lists accumulate — the spelling that needs no quoting.
        @test prefs_of("-Djuliaimg.sysimg=a", "-Djuliaimg.sysimg=b")["juliaimg"]["sysimg"] ==
              ["a", "b"]
        # An empty payload clears rather than appends.
        @test isempty(prefs_of("-Djuliaimg.sysimg=a", "-Djuliaimg.sysimg=")["juliaimg"]["sysimg"])
    end

    @testset "on_repeat = :error rejects every repeat" begin
        # Tested against ArgTools directly: AppBundler's parse_build_args does not
        # forward the keyword unless you add it there.
        schema = Dict("bundler" => "juliaimg", "sysimg" => String[])
        @test_throws ErrorException argtools_prefs(["-Dbundler=a", "-Dbundler=b"], schema;
                                                   on_repeat = :error)
        @test_throws ErrorException argtools_prefs(["-Dsysimg=a", "-Dsysimg=b"], schema;
                                                   on_repeat = :error)
        @test_throws ErrorException argtools_prefs(["-Dbundler=a"], schema;
                                                   on_repeat = :nonsense)
    end

    @testset "unknown keys abort rather than build wrong" begin
        @test_throws Exception prefs_of("-Dbundlr=juliaimg")
        @test occursin("bundler", message_of(() -> prefs_of("-Dbundlr=juliaimg")))
        # An empty key is unknown like any other.
        @test_throws Exception prefs_of("-D=")
        @test_throws Exception prefs_of("-D", "=value")
    end
end


### Layer 3: flags, defaults and the AppBundler config they build.

@testset "parse_build_args" begin

    @testset "the motivating invocation, whole" begin
        # Every token of the documented command line, in one call: positionals,
        # an attached path flag, a bare flag, and three -D forms. Run inside a
        # temp dir because --build-dir is created as a side effect.
        mktempdir() do dir
            cd(dir) do
                config, prefs = parse_build_args(String["--build-dir=build",
                                                  "--selfsign",
                                                  "-Dbundler=juliaimg",
                                                  "-Djuliaimg.selective_assets=true",
                                                  "-Djuliaimg.sysimg=[QMLApp]"])
                @test basename(config[:build_dir]) == "build"
                # Untouched flags keep their defaults alongside the ones given.
                @test config[:target_name] === nothing
                @test config[:password] === nothing
                @test config[:target_arch] === Sys.ARCH
                @test prefs["selfsign"] === true
                @test prefs["bundler"] == "juliaimg"
                @test prefs["juliaimg"]["selective_assets"] === true
                @test prefs["juliaimg"]["sysimg"] == ["QMLApp"]
            end
        end
    end

    @testset "the motivating invocation, escaped form still works" begin
        prefs = prefs_of("-Dbundler=\"juliaimg\"",
                         "-Djuliaimg.selective_assets=true",
                         "-Djuliaimg.sysimg=[\"QMLApp\"]")
        @test prefs["bundler"] == "juliaimg"
        @test prefs["juliaimg"]["selective_assets"] === true
        @test prefs["juliaimg"]["sysimg"] == ["QMLApp"]
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
        config, prefs = parse_build_args(String["--target-name", "My App",
                                          "--target-arch", "aarch64",
                                          "--target-bundle", "dmg",
                                          "--password=  hunter2  ",
                                          "--force",
                                          "-Djuliaimg.sysimg=[QMLApp, AppEnv]"])
        @test config[:target_name] == "My App"
        @test config[:target_arch] === :aarch64
        @test config[:target_bundle] === :dmg
        @test config[:password] == "hunter2"          # stripped, attached or not
        @test prefs["overwrite_target"] === true
        @test prefs["juliaimg"]["sysimg"] == ["QMLApp", "AppEnv"]
        # A repeated flag takes the last value, as -D does under on_repeat = :last.
        @test config_of("--target-arch", "x86_64",
                        "--target-arch", "aarch64")[:target_arch] === :aarch64
    end

    @testset "flag-set preferences" begin
        @test prefs_of("--skipsign")["skipsign"] === true
        @test prefs_of("--debug")["windowed"] === false
    end

    @testset "-D overrides win over flag-set preferences" begin
        @test prefs_of("--selfsign", "-Dselfsign=false")["selfsign"] === false
        # --debug sets compress=false; the override wins whichever order they appear.
        @test prefs_of("-Dcompress=true", "--debug")["compress"] === true
        @test prefs_of("--debug", "-Dcompress=true")["compress"] === true
    end

    @testset "a value holding brackets does not disturb its neighbours" begin
        config, prefs = parse_build_args(String["--password", "ab[cd", "--selfsign"])
        @test config[:password] == "ab[cd"
        @test prefs["selfsign"] === true
    end

    @testset "missing values report properly" begin
        for flag in ("--target-name", "--password", "--target-arch",
                     "--target-bundle", "--build-dir", "-D")
            @testset "$flag" begin
                @test_throws ErrorException parse_build_args(String[flag])
                @test_throws ErrorException parse_build_args(String[flag, "--selfsign"])
            end
        end
    end

    @testset "unknown flags warn but do not abort" begin
        @test_logs (:warn,) match_mode = :any begin
            @test prefs_of("--nonsense", "-Dbundler=juliaimg")["bundler"] == "juliaimg"
        end
    end
end
