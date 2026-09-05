# End to end check against a real AppImage runtime.
#
# Opt in with JULIA_RUN_APPIMAGE_E2E=true and point APPIMAGE_RUNTIME at a runtime binary (see
# https://github.com/AppImage/type2-runtime/releases), or install AppImageRuntime_jll once it is
# registered.
#
# Note that mounting requires `fusermount` on the host. Where it is missing the runtime says so and
# falls back to --appimage-extract-and-run, which exercises the same AppRun and payload; only the
# mount call itself goes untested.

import AppBundler
import AppBundler: AppImage, AppImagePack, bundle, stage, JuliaImgBundle

using Test

const APP = joinpath(pkgdir(AppBundler), "examples", "CmdApp")

function available_runtime()

    path = get(ENV, "APPIMAGE_RUNTIME", "")
    isempty(path) || return isfile(path) ? path : nothing

    return AppBundler.AppImageRuntime.jll_runtime(Sys.ARCH)
end

runtime = available_runtime()

if !Sys.islinux()
    @info "Skipping AppImage end to end test: Linux required"
elseif isnothing(runtime)
    @info "Skipping AppImage end to end test: set APPIMAGE_RUNTIME or install AppImageRuntime_jll"
else

    appimage = AppImage(APP; arch = Sys.ARCH, runtime, preferences = merge(
        AppBundler.Resources.get_project_preferences(APP)["AppBundler"],
        Dict("bundler" => "juliaimg")))

    destination = joinpath(mktempdir(), "$(AppBundler.canonical_target_name(appimage)).AppImage")

    product = JuliaImgBundle(APP; precompile = false)

    bundle(product, appimage, destination)

    @testset "The AppImage is well formed" begin

        @test isfile(destination)
        @test (stat(destination).mode & 0o111) != 0

        # The runtime reports the payload offset it will mount at; it has to agree with what we
        # computed, otherwise the runtime and AppBundler disagree about where the filesystem is.
        reported = parse(Int, strip(read(`$destination --appimage-offset`, String)))
        @test reported == AppImagePack.offset(destination)
        @test reported == filesize(runtime)
    end

    @testset "The payload carries a Julia distribution" begin

        extracted = mktempdir()
        AppImagePack.unpack(destination, extracted)

        @test isfile(joinpath(extracted, "AppRun"))
        @test isfile(joinpath(extracted, "bin", "julia"))
        @test isfile(joinpath(extracted, "etc", "julia", "startup.jl"))
        @test isdir(joinpath(extracted, "share", "julia"))
    end

    @testset "The application runs out of the AppImage" begin

        # CmdApp prints its own LOAD_PATH, DEPOT_PATH, Sys.BINDIR and USER_DATA, which is what
        # makes it possible to check that the depot decision actually took effect on the far side.
        data_home = mktempdir()

        env = copy(ENV)
        env["XDG_DATA_HOME"] = data_home
        delete!(env, "USER_DATA")

        # --appimage-extract-and-run avoids needing fusermount, while still going through the
        # runtime and AppRun exactly as a mounted run would.
        output = read(ignorestatus(setenv(`$destination --appimage-extract-and-run`,
                                          env; dir = mktempdir())), String)

        @test occursin("Sys.BINDIR", output)

        # The default "app" depot: persistent, per user, and never the host's ~/.julia
        @test occursin(joinpath(data_home, "cmdapp"), output)
        @test !occursin(joinpath(homedir(), ".julia") * ",", output)
    end
end
