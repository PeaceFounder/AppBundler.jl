using Base.BinaryPlatforms: arch
using Pkg.BinaryPlatforms: Linux, Windows, MacOS
using .JuliaImg: JuliaImgBundle
using .JuliaC: JuliaCBundle 
import AppEnv


"""
    bundle(product, packaging, destination; force=false, [password=""])

Bundle a Julia application `product` into a platform-specific package at `destination`
by calling [`bundle(setup, config, destination)`](@ref) with `product` staged as the
setup step.

# Arguments
- `product`: The application artifact to bundle. Either a `JuliaImgBundle` or a `JuliaCBundle` 
- `packaging`: The target package format. One of:
  - `DMG` — macOS disk image (`.dmg`). Must be built on macOS.
  - `Snap` — Linux Snap package. Must be built on Linux.
  - `MSIX` — Windows app package (`.msix`). Must be built on Windows.
- `destination`: Output path for the produced package file.

# Keyword Arguments
- `force=false`: Overwrite an existing package at `destination` if `true`.
- `password=""`: Code-signing certificate password. Applicable to `DMG` and `MSIX` targets only.

A warning is emitted when the host OS does not match the target platform, as
cross-platform packaging is not supported.

See also [`stage`](@ref), [`bundle(setup, config, destination)`](@ref).
"""
function bundle(product::JuliaImgBundle, dmg::DMG, destination::String; force = false, password = "")

    bundle(dmg, destination; force, password) do app_stage
        # app_stage always points to app directory
        # app_stage always points to app directory
        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]

        stage(product, joinpath(app_stage, "Contents/Libraries"); platform = MacOS(dmg.arch), runtime_mode = "SANDBOX", app_name, bundle_identifier)

        install(product.startup_file, joinpath(app_stage, "Contents/Libraries/etc/julia/startup.jl"); parameters = dmg.parameters, force = true)

    end

    return
end

function bundle(product::JuliaImgBundle, snap::Snap, destination::String; force = false)

    configure_compiled_modules = JuliaImg.get_project_deps(product.source)
    snap.parameters["PROJECT_DEPS"] = join(configure_compiled_modules, ",")

    bundle(snap, destination; force) do app_stage

        app_name = snap.parameters["APP_NAME"]
        bundle_identifier = snap.parameters["BUNDLE_IDENTIFIER"]
        
        stage(product, app_stage; platform = Linux(snap.arch), runtime_mode = "SANDBOX", app_name, bundle_identifier)
        
        install(product.startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = snap.parameters, force = true)

    end

    return
end

function normalize_executable(path::String)

    tempfile = joinpath(mktempdir(), basename(path))
    mv(path, tempfile)
    cp(tempfile, path)

    return
end

function bundle(product::JuliaImgBundle, msix::MSIX, destination::String; force = false, password = "")

    bundle(msix, destination; force, password) do app_stage
        
        app_name = msix.parameters["APP_NAME"]
        bundle_identifier = msix.parameters["BUNDLE_IDENTIFIER"]

        stage(product, app_stage; platform = Windows(msix.arch), runtime_mode = "SANDBOX", app_name, bundle_identifier)
        mv("$app_stage/libexec/julia/lld.exe", "$app_stage/bin/lld.exe") # julia.exe can't find shared libraries in UWP

        # Executables extracted from tar archives carry Unix-style metadata that causes 
        # Windows AppX validation to fail with "The parameter is incorrect" when launched 
        # from the Start Menu.
        Sys.iswindows() && normalize_executable("$app_stage/bin/julia.exe")
        
        touch("$app_stage/bin/julia.exe") # updating timestamp to avoid Invalid Parameter error

        install(product.startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = msix.parameters, force = true)

        if msix.windowed
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
    end

    return
end

function bundle(product::JuliaCBundle, dmg::DMG, destination::String; force = false, password = "")

    if !Sys.isapple()
        @warn "The build for the DMG will not work as it is not built on macos"
    end

    if dmg.sandboxed_runtime && !dmg.windowed
        @warn "In hardened runtime mode it is a known bug that GUI terminal won't launch"
    end

    bundle(dmg, destination; force, password) do app_stage
        # app_stage always points to app directory
        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]
        stage(product, joinpath(app_stage, "Contents/Libraries"); runtime_mode = "SANDBOX", app_name, bundle_identifier)
    end

    return
end

function bundle(product::JuliaCBundle, snap::Snap, destination::String; force = false)

    if !Sys.islinux()
        @warn "The build for the snap will not work as it is not built on linux"
    end

    bundle(snap, destination; force) do app_stage
        app_name = snap.parameters["APP_NAME"]
        bundle_identifier = snap.parameters["BUNDLE_IDENTIFIER"]
        stage(product, app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)
    end

    return
end

function bundle(product::JuliaCBundle, msix::MSIX, destination::String; password = "", force = false)

    if !Sys.iswindows()
        @warn "The build for MSIX will not work as it is not built on Windows"
    end
    # I need to pass down the arguments here somehow for the template
    bundle(msix, destination; password, force) do app_stage

        app_name = msix.parameters["APP_NAME"]
        bundle_identifier = msix.parameters["BUNDLE_IDENTIFIER"]
        stage(product, app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)        

        if msix.windowed
            WinSubsystem.change_subsystem_inplace(joinpath(app_stage, "bin", "$app_name.exe"); subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
    end

    return
end
