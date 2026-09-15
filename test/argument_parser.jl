# Argument parsing, tested one layer at a time.
#
#   normalize_args   argv -> [option => value].  No schema; one shell word is one value.
#   parse_args[2]    -D payloads -> preferences.  Schema-driven coercion.
#   parse_args[1]    flags -> AppBundler config.  The caller's own rules.
#
# The invocation that motivated the parser, now writable without escapes:
#
#   appbundler build . --build-dir=build --selfsign \
#       -Dbundler=juliaimg -Djuliaimg_selective_assets=true -Djuliaimg_sysimg=[QMLApp]

using AppBundler

using Test

using AppBundler: parse_args, ArgTools
using AppBundler.ArgTools: normalize_args

config_of(argv...) = parse_args(String[argv...])[1]
prefs_of(argv...) = parse_args(String[argv...])[2]

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

    @testset "attached and detached forms are equivalent" begin
        @test normalize_args(["--password", "hunter2"]) == ["--password" => "hunter2"]
        @test normalize_args(["--password=hunter2"]) == ["--password" => "hunter2"]
        @test normalize_args(["--password=dfdfsdf"]) == ["--password" => "dfdfsdf"]
        # Only the first '=' separates option from value.
        @test normalize_args(["--password", "foo=bar"]) == ["--password" => "foo=bar"]
        @test normalize_args(["--password=foo=bar"]) == ["--password" => "foo=bar"]
        @test normalize_args(["-Dbundler=juliaimg"]) == ["-D" => "bundler=juliaimg"]
        @test normalize_args(["-D", "bundler=juliaimg"]) == ["-D" => "bundler=juliaimg"]
    end

    @testset "valueless options" begin
        @test normalize_args(["--selfsign"]) == ["--selfsign" => nothing]
        @test normalize_args(["--selfsign", "--force"]) ==
              ["--selfsign" => nothing, "--force" => nothing]
        @test normalize_args(["-D"]) == ["-D" => nothing]
        @test normalize_args(["-Dselfsign"]) == ["-D" => "selfsign"]
    end

    @testset "an option is never adopted as a value" begin
        @test normalize_args(["--password", "--selfsign"]) ==
              ["--password" => nothing, "--selfsign" => nothing]
        @test normalize_args(["-D", "--selfsign"]) ==
              ["-D" => nothing, "--selfsign" => nothing]
        @test normalize_args(["--password", "-Dfoo=bar"]) ==
              ["--password" => nothing, "-D" => "foo=bar"]
    end

    @testset "a non-option always is" begin
        @test normalize_args(["--password", "-secret"]) == ["--password" => "-secret"]
        @test normalize_args(["--target-name", "My App"]) == ["--target-name" => "My App"]
        @test normalize_args(["--password", "a", "b"]) ==
              ["--password" => "a", "b" => nothing]
        # Ambiguity the rule buys: a boolean option adopts a following
        # positional. Caught downstream by the caller's arity check.
        @test normalize_args(["--selfsign", "build"]) == ["--selfsign" => "build"]
        @test normalize_args(["build", ".", "--selfsign"]) ==
              ["build" => nothing, "." => nothing, "--selfsign" => nothing]
    end

    @testset "a value is one shell word, taken verbatim" begin
        # Brackets, commas and braces are content here; only coercion reads them.
        @test normalize_args(["-Dkey={a, b}"]) == ["-D" => "key={a, b}"]
        @test normalize_args(["--password", "a=b,"]) == ["--password" => "a=b,"]
        @test normalize_args(["--description=Tool for X, Y,"]) ==
              ["--description" => "Tool for X, Y,"]
        @test normalize_args(["-Dpath=\"C:\\\"", "--selfsign"]) ==
              ["-D" => "path=\"C:\\\"", "--selfsign" => nothing]
        # No pass reaches across a shell split, so an open bracket cannot
        # swallow the option after it.
        @test normalize_args(["--filter", "key=[a", "--selfsign]"]) ==
              ["--filter" => "key=[a", "--selfsign]" => nothing]
        @test normalize_args(["--filter", "key=\"[a\"", "--selfsign]"]) ==
              ["--filter" => "key=\"[a\"", "--selfsign]" => nothing]
        # NEW. The attached form truncates at the split rather than rejoining.
        @test normalize_args(["--target-name=My", "App"]) ==
              ["--target-name" => "My", "App" => nothing]
        # NEW. The input array is never modified.
        let raw = ["-Dsysimg=[a,b]", "--force"], before = copy(raw)
            normalize_args(raw)
            @test raw == before
        end
    end

    @testset "one layer of outer quotes comes off" begin
        @test normalize_args(["--password=\"dfdfsdf\""]) == ["--password" => "dfdfsdf"]
        @test normalize_args(["--password", "\"a=b,\""]) == ["--password" => "a=b,"]
        @test normalize_args(["--description=\"Tool for X, Y,\""]) ==
              ["--description" => "Tool for X, Y,"]
        @test normalize_args(["--password=''x''"]) == ["--password" => "'x'"]
        @test normalize_args(["--target-name=\"Bob's Tool\""]) == ["--target-name" => "Bob's Tool"]
        # A single quote inside a word is an apostrophe, never a grouping quote.
        @test normalize_args(["--target-name", "Bob's Tool"]) == ["--target-name" => "Bob's Tool"]
        @test normalize_args(["--target-name=Bob's Tool"]) == ["--target-name" => "Bob's Tool"]
        # The -D payload keeps its quotes; they come off per element, later.
        @test normalize_args(["-Dbundler=\"juliaimg\""]) == ["-D" => "bundler=\"juliaimg\""]
    end

    @testset "empty and edge tokens" begin
        @test normalize_args(String[]) == []
        @test normalize_args(["--"]) == ["--" => nothing]
        @test normalize_args(["-D="]) == ["-D" => "="]
        # An attached empty value is "" rather than nothing, so a `require`-style
        # check accepts it. Legitimate for -D (empty list); questionable for
        # path-like flags, where it reaches mkpath("").
        @test normalize_args(["-Dsysimg="]) == ["-D" => "sysimg="]
        @test normalize_args(["--build-dir="]) == ["--build-dir" => ""]
    end
end


### Layer 2: coercing -D payloads against the schema.

@testset "preferences" begin

    @testset "strings are never type-guessed" begin
        @test prefs_of("-Dbundler=2026")["bundler"] === "2026"
        @test prefs_of("-Dbundler=true")["bundler"] === "true"
        @test prefs_of("-Dbundler=")["bundler"] === ""
        # Only the first '=' splits key from value.
        @test prefs_of("-Dbundler=a=b")["bundler"] == "a=b"
        @test prefs_of("-Dbundler=\"sdsd,sds\"")["bundler"] == "sdsd,sds"
        @test prefs_of("-Dbundler=a\\b")["bundler"] == "a\\b"
        @test prefs_of("-Dbundler=''x''")["bundler"] == "'x'"
        @test prefs_of("-Dbundler=\"\\\"x\\\"\"")["bundler"] == "\\\"x\\\""
        # NEW. An unterminated quote is content in a scalar; only lists scan.
        @test prefs_of("-Dbundler=\"juliaimg")["bundler"] == "\"juliaimg"
    end

    @testset "booleans" begin
        @test prefs_of("-Dselfsign=true")["selfsign"] === true
        @test prefs_of("-Dselfsign=false")["selfsign"] === false
        @test prefs_of("-Dselfsign=\"true\"")["selfsign"] === true
        @test prefs_of("-Dselfsign")["selfsign"] === true   # bare key, Bool only
        @test_throws Exception prefs_of("-Dselfsign=yes")
        @test_throws Exception prefs_of("-Dselfsign=1")
        @test_throws Exception prefs_of("-Dbundler")        # bare key, not a Bool
    end

    @testset "all list spellings converge" begin
        for raw in ("-Djuliaimg_sysimg=[\"QMLApp\",\"AppEnv\"]",
                    "-Djuliaimg_sysimg=[QMLApp,AppEnv]",
                    "-Djuliaimg_sysimg=QMLApp,AppEnv",
                    "-Djuliaimg_sysimg=[QMLApp, AppEnv]")   # one token: quoted by the shell
            @test prefs_of(raw)["juliaimg_sysimg"] == ["QMLApp", "AppEnv"]
        end
    end

    @testset "a bare scalar promotes to a one-element list" begin
        @test prefs_of("-Djuliaimg_sysimg=QMLApp")["juliaimg_sysimg"] == ["QMLApp"]
        @test prefs_of("-Djuliaimg_sysimg=\"QMLApp\"")["juliaimg_sysimg"] == ["QMLApp"]
        # A wholly quoted payload is one element, commas included.
        @test prefs_of("-Djuliaimg_sysimg=\"sdsd,sds\"")["juliaimg_sysimg"] == ["sdsd,sds"]
    end

    @testset "empty lists" begin
        for raw in ("-Djuliaimg_sysimg=", "-Djuliaimg_sysimg=[]")
            @test isempty(prefs_of(raw)["juliaimg_sysimg"])
        end
    end

    @testset "malformed lists abort the whole invocation" begin
        # A trailing comma inside brackets is conventional and ignored.
        @test prefs_of("-Djuliaimg_sysimg=[a,b,]")["juliaimg_sysimg"] == ["a", "b"]
        @test_throws ErrorException prefs_of("-Djuliaimg_sysimg=[,a]")
        # Unterminated: must not silently swallow the following option.
        @test_throws Exception prefs_of("-Djuliaimg_sysimg=[QMLApp,")
        @test_throws Exception prefs_of("-Djuliaimg_sysimg=[QMLApp,", "--selfsign")
        @test_throws ErrorException prefs_of("-Djuliaimg_sysimg=a,", "--selfsign")
    end

    @testset "a quoted bracket is content, not an open delimiter" begin
        prefs = prefs_of("-Dbundler=\"[sdfsdffsdf\"", "--force")
        @test prefs["bundler"] == "[sdfsdffsdf"
        @test prefs["overwrite_target"] === true
    end

    @testset "attached and detached -D forms agree" begin
        @test prefs_of("-Dbundler=juliaimg")["bundler"] ==
              prefs_of("-D", "bundler=juliaimg")["bundler"] == "juliaimg"
        @test prefs_of("-D", "selfsign")["selfsign"] === true   # detached bare bool
    end

    @testset "a repeated key" begin
        # NEW. Scalars take the last value, matching a repeated flag.
        @test prefs_of("-Dbundler=first", "-Dbundler=second")["bundler"] == "second"
        # NEW. Lists accumulate — the spelling that needs no quoting.
        @test prefs_of("-Djuliaimg_sysimg=a", "-Djuliaimg_sysimg=b")["juliaimg_sysimg"] ==
              ["a", "b"]
        # NEW. An empty payload clears rather than appends.
        @test isempty(prefs_of("-Djuliaimg_sysimg=a", "-Djuliaimg_sysimg=")["juliaimg_sysimg"])
    end

    @testset "on_repeat = :error rejects every repeat" begin
        # NEW. Tested against ArgTools directly: AppBundler's parse_args does not
        # forward the keyword unless you add it there.
        schema = Dict("bundler" => "juliaimg", "sysimg" => String[])
        @test_throws ErrorException ArgTools.parse_args(["-Dbundler=a", "-Dbundler=b"];
                                                        schema, on_repeat = :error)
        @test_throws ErrorException ArgTools.parse_args(["-Dsysimg=a", "-Dsysimg=b"];
                                                        schema, on_repeat = :error)
        @test ArgTools.parse_args(["-Dsysimg=a", "-Dsysimg=b"]; schema)[2]["sysimg"] == ["a", "b"]
        @test ArgTools.parse_args(["-Dbundler=a", "-Dbundler=b"]; schema)[2]["bundler"] == "b"
        @test_throws ErrorException ArgTools.parse_args(["-Dbundler=a"];
                                                        schema, on_repeat = :nonsense)
    end

    @testset "unknown keys abort rather than build wrong" begin
        @test_throws Exception prefs_of("-Djuliaimg_selective_asset=true")
        @test_throws Exception prefs_of("-Dbundlr=juliaimg")
        @test occursin("bundler", message_of(() -> prefs_of("-Dbundlr=juliaimg")))
        # An empty key is unknown like any other.
        @test_throws Exception prefs_of("-D=")
        @test_throws Exception prefs_of("-D", "=value")
        # NOTE: 'key' is not in the schema, so this only exercises the unknown-key
        # path — it says nothing about how '{a=1}' would coerce.
        @test_throws Exception prefs_of("-Dkey={a=1}")
    end
end


### Layer 3: flags, defaults and the AppBundler config they build.

@testset "parse_args" begin

    @testset "the motivating invocation" begin
        prefs = prefs_of("--selfsign",
                         "-Dbundler=juliaimg",
                         "-Djuliaimg_selective_assets=true",
                         "-Djuliaimg_sysimg=QMLApp")
        @test prefs["bundler"] == "juliaimg"
        @test prefs["juliaimg_selective_assets"] === true
        @test prefs["juliaimg_sysimg"] == ["QMLApp"]
        @test prefs["selfsign"] === true
    end

    @testset "the motivating invocation, escaped form still works" begin
        prefs = prefs_of("-Dbundler=\"juliaimg\"",
                         "-Djuliaimg_selective_assets=true",
                         "-Djuliaimg_sysimg=[\"QMLApp\"]")
        @test prefs["bundler"] == "juliaimg"
        @test prefs["juliaimg_selective_assets"] === true
        @test prefs["juliaimg_sysimg"] == ["QMLApp"]
    end

    @testset "defaults with no arguments" begin
        config, prefs = parse_args(String[])
        @test isdir(config[:build_dir])
        @test config[:target_name] === nothing
        @test config[:password] === nothing
        @test config[:target_arch] === Sys.ARCH
        @test isempty(prefs)
    end

    @testset "flags carry their values into the config" begin
        config, prefs = parse_args(String["--target-name", "My App",
                                          "--target-arch", "aarch64",
                                          "--target-bundle", "dmg",
                                          "--password", "  hunter2  ",
                                          "--force",
                                          "-Djuliaimg_sysimg=[QMLApp, AppEnv]"])
        @test config[:target_name] == "My App"
        @test config[:target_arch] === :aarch64
        @test config[:target_bundle] === :dmg
        @test config[:password] == "hunter2"
        @test prefs["overwrite_target"] === true
        @test prefs["juliaimg_sysimg"] == ["QMLApp", "AppEnv"]
    end

    @testset "flag-set preferences" begin
        @test prefs_of("--skipsign")["skipsign"] === true
        @test prefs_of("--debug")["windowed"] === false
    end

    @testset "a value holding brackets does not disturb its neighbours" begin
        config, prefs = parse_args(String["--password", "ab[cd", "--selfsign"])
        @test config[:password] == "ab[cd"
        @test prefs["selfsign"] === true
        @test config_of("--target-name", "Bob's App", "--force")[:target_name] == "Bob's App"
    end

    @testset "-D overrides win over flag-set preferences" begin
        @test prefs_of("--selfsign", "-Dselfsign=false")["selfsign"] === false
        # --debug sets compress=false; the override wins whichever order they appear.
        @test prefs_of("-Dcompress=true", "--debug")["compress"] === true
        @test prefs_of("--debug", "-Dcompress=true")["compress"] === true
    end

    @testset "a repeated flag takes the last value" begin
        # Matches -D under the default on_repeat = :last.
        @test config_of("--target-arch", "x86_64", "--target-arch", "aarch64")[:target_arch] === :aarch64
    end

    @testset "an attached value is stripped like a detached one" begin
        @test config_of("--password=  hunter2  ")[:password] == "hunter2"
    end

    @testset "missing values report properly" begin
        for flag in ("--target-name", "--password", "--target-arch",
                     "--target-bundle", "--build-dir", "-D")
            @testset "$flag" begin
                @test_throws ErrorException parse_args(String[flag])
                @test_throws ErrorException parse_args(String[flag, "--selfsign"])
            end
        end
    end

    @testset "unknown flags warn but do not abort" begin
        @test_logs (:warn,) match_mode = :any begin
            @test prefs_of("--nonsense", "-Dbundler=juliaimg")["bundler"] == "juliaimg"
        end
    end
end
