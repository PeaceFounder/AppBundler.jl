# Currently there is a limitation
# appbundler build . --build-dir=build --selfsign -Dbundler=\"juliaimg\" -Djuliaimg_selective_assets=true -Djuliaimg_sysimg=[\"QMLApp\"]

using AppBundler

using Test

using AppBundler: parse_args, CLIParser
using AppBundler.CLIParser: normalize_args

# Original tests from integrity.jl
@test normalize_args(["--password=dfdfsdf"]) == ["--password" => "dfdfsdf"]
@test normalize_args(["--password=\"dfdfsdf\""]) == ["--password" => "dfdfsdf"]


@testset "normalize_args" begin

    @testset "attached and detached forms are equivalent" begin
        @test normalize_args(["--password", "hunter2"]) == ["--password" => "hunter2"]
        @test normalize_args(["--password=hunter2"]) == ["--password" => "hunter2"]
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

    @testset "healing: unclosed bracket or quote" begin
        @test normalize_args(["-Dsysimg=[QMLApp,", "AppEnv]"]) ==
              ["-D" => "sysimg=[QMLApp, AppEnv]"]
        @test normalize_args(["-Dsysimg=\"[QMLApp,", "AppEnv]\""]) ==
              ["-D" => "sysimg=\"[QMLApp, AppEnv]\""]
        @test normalize_args(["-Ds=[A,", "B,", "C]"]) == ["-D" => "s=[A, B, C]"]
        # Absorbed tokens may themselves look like options.
        @test normalize_args(["-Dsysimg=[a,", "-b]"]) == ["-D" => "sysimg=[a, -b]"]
        @test normalize_args(["-Dsysimg=[a,", "--selfsign]"]) ==
              ["-D" => "sysimg=[a, --selfsign]"]
        # Already balanced — nothing to heal.
        @test normalize_args(["-Dsysimg=[\"QMLApp\"]"]) == ["-D" => "sysimg=[\"QMLApp\"]"]
        # A quoted bracket is content, not an open delimiter.
        @test normalize_args(["-Dbundler=\"[sdfsdffsdf\"", "--force"]) ==
              ["-D" => "bundler=\"[sdfsdffsdf\"", "--force" => nothing]
    end

    @testset "healing: trailing comma" begin
        @test_throws ErrorException normalize_args(["-Dsysimg=QMLApp,", "AppEnv"]) ==
              ["-D" => "sysimg=QMLApp, AppEnv"]
        @test_throws ErrorException normalize_args(["-Dsysimg=a,", "--selfsign"]) ==
              ["-D" => "sysimg=a, --selfsign"]
        @test_throws ErrorException normalize_args(["-Dsysimg=a,", "[b,", "c]"]) == ["-D" => "sysimg=a, [b, c]"]
        @test normalize_args(["-Dsysimg=a,b"]) == ["-D" => "sysimg=a,b"]
    end

    @testset "tokens that must not be healed" begin
        # No '=' in the token, so it is a plain value.
        @test normalize_args(["--password", "ab[cd", "--selfsign"]) ==
              ["--password" => "ab[cd", "--selfsign" => nothing]
        # Balanced with no trailing comma: no continuation signal exists, so the
        # attached form silently truncates. Use the detached form for spaces.
        @test normalize_args(["--target-name=My", "App"]) ==
              ["--target-name" => "My", "App" => nothing]
        # A single quote in ARGS is an apostrophe, never a grouping quote.
        @test normalize_args(["--target-name", "Bob's App"]) ==
              ["--target-name" => "Bob's App"]
    end

    @testset "unterminated values" begin
        @test_throws ErrorException normalize_args(["-Dsysimg=[QMLApp,"])
        @test_throws ErrorException normalize_args(["-Dsysimg=a,"])
        @test_throws ErrorException normalize_args(["-Dbundler=\"juliaimg"])
        # Absorbs to the end of ARGS and is still unbalanced.
        @test_throws ErrorException normalize_args(["-Dsysimg=[a,", "--selfsign"])
    end

    @testset "empty input" begin
        @test normalize_args(String[]) == []
    end

    @testset "empty attached values" begin
        # An attached empty value is "" rather than nothing, so a `require`-style
        # check accepts it. Legitimate for -D (empty list); questionable for
        # path-like flags, where it reaches mkpath("").
        @test normalize_args(["-Dsysimg="]) == ["-D" => "sysimg="]
        @test normalize_args(["--build-dir="]) == ["--build-dir" => ""]
        @test normalize_args(["--"]) == ["--" => nothing]
    end
end

prefs_of(v...) = parse_args(String[v...])[2]
config_of(v...) = parse_args(String[v...])[1]

@testset "parse_args" begin

    @testset "the motivating invocation, short form" begin
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

    @testset "all list spellings converge" begin
        # Single tokens — the shell kept these intact.
        for raw in ("-Djuliaimg_sysimg=[\"QMLApp\",\"AppEnv\"]",
                    "-Djuliaimg_sysimg=[QMLApp,AppEnv]",
                    "-Djuliaimg_sysimg=QMLApp,AppEnv")
            @test prefs_of(raw)["juliaimg_sysimg"] == ["QMLApp", "AppEnv"]
        end
        # Split by the shell on the unquoted space — healing must rejoin them.
        @test prefs_of("-Djuliaimg_sysimg=[QMLApp,", "AppEnv]")["juliaimg_sysimg"] ==
              ["QMLApp", "AppEnv"]
        @test prefs_of("-Djuliaimg_sysimg=\"[QMLApp,", "AppEnv]\"")["juliaimg_sysimg"] ==
              ["QMLApp", "AppEnv"]
    end

    @testset "a bare scalar promotes to a one-element list" begin
        @test prefs_of("-Djuliaimg_sysimg=QMLApp")["juliaimg_sysimg"] == ["QMLApp"]
        @test prefs_of("-Djuliaimg_sysimg=\"QMLApp\"")["juliaimg_sysimg"] == ["QMLApp"]
    end

    @testset "empty lists" begin
        for raw in ("-Djuliaimg_sysimg=", "-Djuliaimg_sysimg=[]")
            @test isempty(prefs_of(raw)["juliaimg_sysimg"])
        end
    end

    @testset "strings are never type-guessed" begin
        @test prefs_of("-Dbundler=2026")["bundler"] === "2026"
        @test prefs_of("-Dbundler=true")["bundler"] === "true"
        @test prefs_of("-Dbundler=")["bundler"] === ""
        # Only the first '=' splits key from value.
        @test prefs_of("-Dbundler=a=b")["bundler"] == "a=b"
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

    @testset "attached and detached -D forms agree" begin
        @test prefs_of("-Dbundler=juliaimg")["bundler"] ==
              prefs_of("-D", "bundler=juliaimg")["bundler"] == "juliaimg"
        @test prefs_of("-D", "juliaimg_sysimg=[QMLApp,", "AppEnv]")["juliaimg_sysimg"] ==
              ["QMLApp", "AppEnv"]
    end

    @testset "-D overrides win over flag-set preferences" begin
        @test prefs_of("--selfsign", "-Dselfsign=false")["selfsign"] === false
        # --debug sets compress=false; the override wins whichever order they appear.
        @test prefs_of("-Dcompress=true", "--debug")["compress"] === true
        @test prefs_of("--debug", "-Dcompress=true")["compress"] === true
    end

    @testset "repeated keys: last one wins" begin
        @test prefs_of("-Dbundler=first", "-Dbundler=second")["bundler"] == "second"
    end

    @testset "flags unrelated to -D are unaffected by healing" begin
        config, prefs = parse_args(String["--target-name", "My App",
                                          "--target-arch", "aarch64",
                                          "--target-bundle", "dmg",
                                          "--password", "  hunter2  ",
                                          "--force",
                                          "-Djuliaimg_sysimg=[QMLApp,", "AppEnv]"])
        @test config[:target_name] == "My App"
        @test config[:target_arch] === :aarch64
        @test config[:target_bundle] === :dmg
        @test config[:password] == "hunter2"
        @test prefs["overwrite_target"] === true
        @test prefs["juliaimg_sysimg"] == ["QMLApp", "AppEnv"]
    end

    @testset "values with no '=' are never absorbed" begin
        # Guards --password 'ab[cd' from swallowing the next argument.
        config, prefs = parse_args(String["--password", "ab[cd", "--selfsign"])
        @test config[:password] == "ab[cd"
        @test prefs["selfsign"] === true
        # A single quote in ARGS is an apostrophe, never a grouping quote.
        @test config_of("--target-name", "Bob's App", "--force")[:target_name] == "Bob's App"
    end

    @testset "a quoted bracket is content, not an open delimiter" begin
        # Must not absorb --force looking for a closing ']'.
        prefs = prefs_of("-Dbundler=\"[sdfsdffsdf\"", "--force")
        @test prefs["bundler"] == "[sdfsdffsdf"
        @test prefs["overwrite_target"] === true
    end

    @testset "an unterminated list aborts the whole invocation" begin
        # Must not silently swallow --selfsign into the list.
        @test_throws Exception prefs_of("-Djuliaimg_sysimg=[QMLApp,", "--selfsign")
        @test_throws Exception prefs_of("-Djuliaimg_sysimg=[QMLApp,")
        @test_throws Exception prefs_of("-Dbundler=\"juliaimg")
    end

    @testset "typos in preference names abort rather than build wrong" begin
        @test_throws Exception prefs_of("-Djuliaimg_selective_asset=true")
        @test_throws Exception prefs_of("-Dbundlr=juliaimg")
        err = try
            prefs_of("-Dbundlr=juliaimg"); nothing
        catch e
            sprint(showerror, e)
        end
        @test err !== nothing && occursin("bundler", err)
    end

    @testset "defaults with no arguments" begin
        config, prefs = parse_args(String[])
        @test isdir(config[:build_dir])
        @test config[:target_name] === nothing
        @test config[:password] === nothing
        @test config[:target_arch] === Sys.ARCH
        @test isempty(prefs)
    end

    @testset "unknown flags warn but do not abort" begin
        @test_logs (:warn,) match_mode = :any begin
            @test prefs_of("--nonsense", "-Dbundler=juliaimg")["bundler"] == "juliaimg"
        end
    end
end


# Currently failing — these branches do not bounds-check, so they throw
# BoundsError instead of a usable message. Remove @test_broken once the
# `i > length(args)` guard is applied uniformly (see --build-dir for the shape).
@testset "missing values report properly" begin
    for flag in ("--target-name", "--password", "--target-arch",
                 "--target-bundle", "--build-dir", "-D")
        @testset "$flag" begin
            @test_throws ErrorException parse_args(String[flag])
            @test_throws ErrorException parse_args(String[flag, "--selfsign"])
        end
    end
end

@test normalize_args(["--password=''x''"]) == ["--password" => "'x'"]
@test prefs_of("-Dbundler=''x''")["bundler"] == "'x'"
@test prefs_of("-Dbundler=\"\\\"x\\\"\"")["bundler"] == "\\\"x\\\""

@test normalize_args(["-Dpath=\"C:\\\"", "--selfsign"]) ==
      ["-D" => "path=\"C:\\\"", "--selfsign" => nothing]
@test prefs_of("-Dbundler=a\\b")["bundler"] == "a\\b"
@test normalize_args(["-Dpath=\"C:\\\"", "--selfsign"]) == ["-D" => "path=\"C:\\\"", "--selfsign" => nothing]

normalize_args(["-Dbundler=\"juliaimg\""]) == ["-D" => "bundler=\"juliaimg\""]

@test_throws ErrorException prefs_of("-Djuliaimg_sysimg=a,", "--selfsign")
#@test prefs["juliaimg_sysimg"] == ["a", "--selfsign"]
#@test !haskey(prefs, "selfsign")          # deliberately NOT set

@test prefs_of("-Djuliaimg_sysimg=[a,b,]")["juliaimg_sysimg"] == ["a", "b", ""]
@test prefs_of("-Djuliaimg_sysimg=[,a]")["juliaimg_sysimg"] == ["", "a"]

@test normalize_args(["-D="]) == ["-D" => "="]
@test_throws Exception prefs_of("-D=")              # empty key
@test_throws Exception prefs_of("-D", "=value")
@test prefs_of("-D", "selfsign")["selfsign"] === true    # detached bare bool


@test normalize_args(["-Dkey={a,", "b}"]) == ["-D" => "key={a, b}"]
@test_throws Exception prefs_of("-Dkey={a=1}")


# --skipsign never appears in any test
@test prefs_of("--skipsign")["skipsign"] === true

# repeated non-D flags
@test config_of("--target-arch", "x86_64", "--target-arch", "aarch64")[:target_arch] === :aarch64

# attached --password keeps the strip()
@test config_of("--password=  hunter2  ")[:password] == "hunter2"

# normalize_args must not mutate its input
raw = ["-Dsysimg=[a,", "b]"]; before = copy(raw)
normalize_args(raw); @test raw == before

# --debug sets windowed, which is never asserted
@test prefs_of("--debug")["windowed"] === false

@test prefs_of("-Dbundler=\"sdsd,sds\"")["bundler"] == "sdsd,sds"
@test prefs_of("-Djuliaimg_sysimg=\"sdsd,sds\"")["juliaimg_sysimg"] == ["sdsd", "sds"]
