# `appbundler build` arguments: flags, defaults and the config they build.
#
# Tokenizing and coercing -D values are Knobs' business and tested there
# (Knobs/test/parsing.jl); this file tests AppBundler's own option loop.
#
# The invocation that motivated the parser, now writable without escapes:
#
#   appbundler build . --build-dir=build --selfsign \
#       -Dbundler=juliaimg -Djuliaimg.selective_assets=true -Djuliaimg.sysimg=[QMLApp]

using AppBundler
using Test

using AppBundler: parse_build_args

config_of(args) = parse_build_args(String.(args))[1]
prefs_of(args) = parse_build_args(String.(args))[2]

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
