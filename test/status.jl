using Test
using TOML
using AppBundler
using AppBundler.PrefTools: preferences_status, PreferenceStatus

# Replace with however you obtain the flat schema (dotted keys => spec)
#const SCHEMA = AppBundler.get_preferences_schema()

const SCHEMA = AppBundler.LOCAL_PREFERENCES_SCHEMA

const DEFAULTS = get(TOML.parsefile(joinpath(pkgdir(AppBundler), "LocalPreferences.toml")), "AppBundler", Dict{String,Any}())

function write_preferences(dir, prefs; section = "AppBundler")
    open(joinpath(dir, "LocalPreferences.toml"), "w") do io
        TOML.print(io, Dict(section => prefs))
    end
end

entry(entries, key) = only(filter(e -> e.key == key, entries))
keys_with(entries, status) = Set(e.key for e in entries if e.status == status)

@testset "preferences_status(project, schema)" begin

    @testset "no LocalPreferences.toml in project" begin
        mktempdir() do dir
            entries = preferences_status(dir, SCHEMA)

            @test isempty(keys_with(entries, PreferenceStatus.EXPLICIT))
            @test entry(entries, "dmg.compression").status == PreferenceStatus.DEFAULT
            @test entry(entries, "dmg.compression").value == DEFAULTS["dmg"]["compression"]
        end
    end

    @testset "project keys are explicit" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp", "windowed" => true))
            entries = preferences_status(dir, SCHEMA)

            @test entry(entries, "app_name").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "app_name").value == "GLApp"
            @test entry(entries, "windowed").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "windowed").value == true
        end
    end

    @testset "nested project keys are explicit, even when equal to default" begin
        mktempdir() do dir
            value = DEFAULTS["dmg"]["hardened_runtime"]
            write_preferences(dir, Dict("dmg" => Dict("hardened_runtime" => value)))
            entries = preferences_status(dir, SCHEMA)

            @test entry(entries, "dmg.hardened_runtime").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "dmg.hardened_runtime").value == value
            @test entry(entries, "dmg.compression").status == PreferenceStatus.DEFAULT
        end
    end

    @testset "defines override project file" begin
        mktempdir() do dir
            write_preferences(dir, Dict("windowed" => false))
            entries = preferences_status(dir, SCHEMA; defines = Pair{String,Any}["windowed" => true])

            @test entry(entries, "windowed").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "windowed").value == true

            # The file on disk is left untouched
            on_disk = TOML.parsefile(joinpath(dir, "LocalPreferences.toml"))
            @test on_disk["AppBundler"]["windowed"] == false
        end
    end

    @testset "defines without project file are explicit" begin
        mktempdir() do dir
            entries = preferences_status(dir, SCHEMA; defines = Pair{String,Any}["app_name" => "FromCLI"])

            @test entry(entries, "app_name").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "app_name").value == "FromCLI"
        end
    end

    @testset "inferred keys" begin
        mktempdir() do dir
            infer!(prefs) = (prefs["module_name"] = "GLApp"; prefs)
            entries = preferences_status(dir, SCHEMA; infer!)

            @test entry(entries, "module_name").status == PreferenceStatus.INFERRED
            @test entry(entries, "module_name").value == "GLApp"
        end
    end

    @testset "failed inference keeps partial results and does not throw" begin
        mktempdir() do dir
            function infer!(prefs)
                prefs["module_name"] = "GLApp"
                error("inference failed")
            end

            entries = @test_nowarn preferences_status(dir, SCHEMA; infer!)

            @test entry(entries, "module_name").status == PreferenceStatus.INFERRED
            @test entry(entries, "app_exe").status == PreferenceStatus.ERROR
            @test isnothing(entry(entries, "app_exe").value)
        end
    end

    @testset "uninferred schema keys are errors with value nothing" begin
        mktempdir() do dir
            entries = preferences_status(dir, SCHEMA)  # infer! = identity

            missing = setdiff(keys(SCHEMA), keys(AppBundler.PrefTools.flatten_schema(DEFAULTS)))
            for key in missing
                @test entry(entries, key).status == PreferenceStatus.ERROR
                @test isnothing(entry(entries, key).value)
            end
        end
    end

    @testset "invalid value is an error and keeps its value" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => false))
            entries = preferences_status(dir, SCHEMA)

            @test entry(entries, "app_name").status == PreferenceStatus.ERROR
            @test entry(entries, "app_name").value == false
        end
    end

    @testset "unknown key is an error" begin
        mktempdir() do dir
            write_preferences(dir, Dict("not_a_preference" => 1))
            entries = preferences_status(dir, SCHEMA)

            @test entry(entries, "not_a_preference").status == PreferenceStatus.ERROR
            @test entry(entries, "not_a_preference").value == 1
        end
    end

    @testset "custom section" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp"); section = "Other")

            entries = preferences_status(dir, SCHEMA; section = "Other")
            @test entry(entries, "app_name").status == PreferenceStatus.EXPLICIT

            # With the default section, the [Other] table is ignored
            entries = preferences_status(dir, SCHEMA)
            @test entry(entries, "app_name").status != PreferenceStatus.EXPLICIT
        end
    end

    @testset "entries sorted by status, then key" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp", "windowed" => true))
            entries = preferences_status(dir, SCHEMA)

            @test issorted(entries; by = e -> (e.status, e.key))
            @test allunique(e.key for e in entries)
        end
    end
end


@testset "print_preferences" begin

    colored_io() = IOContext(IOBuffer(), :color => true)
 
    @testset "normal state" begin
        project_dir = joinpath(pkgdir(AppBundler), "examples", "GLApp")  # any valid example project
 
        io = colored_io()
        AppBundler.print_preferences(io, project_dir)
        AppBundler.print_overrides(io, project_dir)
        @test true
    end
 
    @testset "error state" begin
        mktempdir() do project_dir
            # No Project.toml, so inference fails; plus an invalid value
            write_preferences(project_dir, Dict("app_name" => false))
            
            io = colored_io()
            AppBundler.main_status(project_dir, ["--preferences"]; io)
            @test true
        end
    end
end
