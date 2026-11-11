using Test
using TOML
using AppBundler
using AppBundler: preferences_status, PreferenceStatus

const DEFAULTS = get(TOML.parsefile(joinpath(pkgdir(AppBundler), "LocalPreferences.toml")), "AppBundler", Dict{String,Any}())

function write_preferences(dir, prefs; section = "AppBundler")
    open(joinpath(dir, "LocalPreferences.toml"), "w") do io
        TOML.print(io, Dict(section => prefs))
    end
end

"""A minimal project named `name`; `main = false` leaves out `src/<name>.jl`."""
function write_project(dir, name; main = true)
    write(joinpath(dir, "Project.toml"), "name = \"$name\"\nversion = \"1.2.3\"\n")
    if main
        mkpath(joinpath(dir, "src"))
        write(joinpath(dir, "src", "$name.jl"), "module $name end\n")
    end
    return dir
end

entry(entries, key) = only(filter(e -> e.key == key, entries))
keys_with(entries, status) = Set(e.key for e in entries if e.status == status)

@testset "preferences_status(project)" begin

    @testset "no LocalPreferences.toml in project" begin
        mktempdir() do dir
            entries = preferences_status(dir)

            @test isempty(keys_with(entries, PreferenceStatus.EXPLICIT))
            @test entry(entries, "dmg.compression").status == PreferenceStatus.DEFAULT
            @test entry(entries, "dmg.compression").value == DEFAULTS["dmg"]["compression"]
        end
    end

    @testset "project keys are explicit" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp", "windowed" => true))
            entries = preferences_status(dir)

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
            entries = preferences_status(dir)

            @test entry(entries, "dmg.hardened_runtime").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "dmg.hardened_runtime").value == value
            @test entry(entries, "dmg.compression").status == PreferenceStatus.DEFAULT
        end
    end

    @testset "defines override project file" begin
        mktempdir() do dir
            write_preferences(dir, Dict("windowed" => false))
            entries = preferences_status(dir; defines = Pair{String,Any}["windowed" => true])

            @test entry(entries, "windowed").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "windowed").value == true

            # The file on disk is left untouched
            on_disk = TOML.parsefile(joinpath(dir, "LocalPreferences.toml"))
            @test on_disk["AppBundler"]["windowed"] == false
        end
    end

    @testset "defines without project file are explicit" begin
        mktempdir() do dir
            entries = preferences_status(dir; defines = Pair{String,Any}["app_name" => "FromCLI"])

            @test entry(entries, "app_name").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "app_name").value == "FromCLI"
            # Inference follows the final value, wherever it came from
            @test entry(entries, "app_exe").status == PreferenceStatus.INFERRED
            @test entry(entries, "app_exe").value == "fromcli"
        end
    end

    @testset "inferred keys" begin
        mktempdir() do dir
            write_project(dir, "Demo")
            entries = preferences_status(dir)

            @test entry(entries, "app_name").status == PreferenceStatus.INFERRED
            @test entry(entries, "app_name").value == "Demo"
            @test entry(entries, "app_exe").value == "demo"
            @test entry(entries, "version").value == "1.2.3"
            @test entry(entries, "bundle_identifier").value == "org.appbundler.demo"
            @test entry(entries, "module_name").status == PreferenceStatus.INFERRED
            @test entry(entries, "module_name").value == "Demo"
            @test entry(entries, "snap.command").value == ["bin/julia", "-m", "Demo"]
            @test entry(entries, "dmg.command").value == ["Libraries/bin/julia", "--eval", "using Demo", "--"]
            @test entry(entries, "msix.command").value == ["bin\\julia.exe", "--eval", "using Demo"]
            @test isempty(keys_with(entries, PreferenceStatus.ERROR))
        end
    end

    @testset "juliac and mainless builds launch an executable" begin
        mktempdir() do dir
            write_project(dir, "Demo")

            entries = preferences_status(dir; defines = Pair{String,Any}["bundler" => "juliac"])
            @test entry(entries, "module_name").value == ""
            @test entry(entries, "snap.command").value == ["bin/demo"]
            @test entry(entries, "msix.command").value == ["bin\\demo.exe"]

            entries = preferences_status(dir; defines = Pair{String,Any}["juliaimg.mainless" => true])
            @test entry(entries, "appimage.command").value == ["bin/julia"]
            @test entry(entries, "dmg.command").value == ["Libraries/bin/julia"]
        end
    end

    @testset "an explicit command wins over inference" begin
        mktempdir() do dir
            write_project(dir, "Demo")
            write_preferences(dir, Dict("snap" => Dict("command" => ["bin/custom"])))
            entries = preferences_status(dir)

            @test entry(entries, "snap.command").status == PreferenceStatus.EXPLICIT
            @test entry(entries, "snap.command").value == ["bin/custom"]
        end
    end

    @testset "failed inference stays local and does not throw" begin
        mktempdir() do dir
            write_project(dir, "Demo"; main = false)          # no src/Demo.jl to run
            entries = @test_nowarn preferences_status(dir)

            @test entry(entries, "module_name").status == PreferenceStatus.ERROR
            @test entry(entries, "snap.command").status == PreferenceStatus.ERROR
            @test isnothing(entry(entries, "snap.command").value)
            # Keys that do not depend on the module are unaffected
            @test entry(entries, "app_exe").status == PreferenceStatus.INFERRED
            @test entry(entries, "app_exe").value == "demo"
        end
    end

    @testset "uninferable keys are errors with value nothing" begin
        mktempdir() do dir                                     # no Project.toml at all
            entries = preferences_status(dir)

            for key in ("app_name", "app_exe", "version", "bundle_identifier")
                @test entry(entries, key).status == PreferenceStatus.ERROR
                @test isnothing(entry(entries, key).value)
            end
        end
    end

    @testset "invalid value is an error and keeps its value" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => false))
            entries = preferences_status(dir)

            @test entry(entries, "app_name").status == PreferenceStatus.ERROR
            @test entry(entries, "app_name").value == false
        end
    end

    @testset "unknown key is an error" begin
        mktempdir() do dir
            write_preferences(dir, Dict("not_a_preference" => 1))
            entries = preferences_status(dir)

            @test entry(entries, "not_a_preference").status == PreferenceStatus.ERROR
            @test entry(entries, "not_a_preference").value == 1
        end
    end

    @testset "other sections are ignored" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp"); section = "Other")
            entries = preferences_status(dir)
            @test entry(entries, "app_name").status != PreferenceStatus.EXPLICIT
        end
    end

    @testset "entries sorted by status, then key" begin
        mktempdir() do dir
            write_preferences(dir, Dict("app_name" => "GLApp", "windowed" => true))
            entries = preferences_status(dir)

            @test issorted(entries; by = e -> (e.status, e.key))
            @test allunique(e.key for e in entries)
        end
    end
end


@testset "project_preferences" begin

    @testset "resolved and nested" begin
        mktempdir() do dir
            write_project(dir, "Demo")
            write_preferences(dir, Dict("dmg" => Dict("backend" => "hfsplus")))
            prefs = AppBundler.project_preferences(dir; defines = Pair{String,Any}["compress" => false])

            @test prefs["dmg"]["backend"] == "hfsplus"
            @test prefs["dmg"]["compression"] == DEFAULTS["dmg"]["compression"]
            @test prefs["compress"] == false
            @test prefs["app_name"] == "Demo"
        end
    end

    @testset "load_layer reads one section, flattened" begin
        mktempdir() do dir
            path = joinpath(dir, "LocalPreferences.toml")
            @test AppBundler.load_layer(path) == []                      # missing file
            open(path, "w") do io
                TOML.print(io, Dict("AppBundler" => Dict("dmg" => Dict("backend" => "hfsplus"), "windowed" => true),
                                    "Demo" => Dict("assets" => ["data"])))
            end
            @test AppBundler.load_layer(path) == ["dmg.backend" => "hfsplus", "windowed" => true]
            @test AppBundler.load_layer(path; section = "Demo") == ["assets" => ["data"]]
            @test AppBundler.load_layer(path; section = "Missing") == []
        end
    end

    @testset "every problem is reported" begin
        mktempdir() do dir
            write_project(dir, "Demo")
            write_preferences(dir, Dict("dmg" => Dict("backend" => "hfs"), "compres" => true))
            err = try AppBundler.project_preferences(dir); "" catch e; sprint(showerror, e) end

            @test occursin("dmg.backend: LocalPreferences.toml: expects one of", err)
            @test occursin("did you mean 'compress'", err)
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

    @testset "status shows -D overrides" begin
        mktempdir() do project_dir
            write_project(project_dir, "Demo")
            io = IOBuffer()
            AppBundler.main_status(project_dir, ["--preferences", "-Dbundler=juliac"]; io)
            @test occursin(r"bundler\s+= \"juliac\"", String(take!(io)))
        end
    end
end
