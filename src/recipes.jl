using Base.BinaryPlatforms: arch
using Pkg.BinaryPlatforms: Linux, Windows, MacOS
using .Stage: JuliaAppBundle
using .JuliaC: JuliaCBundle 
import AppEnv

# function install_config(config_path, parameters)
    
#     (; stdlib_project_name) = AppEnv.load_config(config_path)
#     runtime_mode = "SANDBOX"
#     app_name = parameters["APP_NAME"]
#     bundle_identifier = parameters["BUNDLE_IDENTIFIER"]

#     AppEnv.save_config(config_path; runtime_mode, stdlib_project_name, app_name, bundle_identifier)
    
#     return
# end

function bundle(product::JuliaAppBundle, dmg::DMG, destination::String; compress::Bool = isext(destination, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), target_arch = Sys.ARCH)

    predicate = :JULIA_APP_BUNDLE
    
    bundle(dmg, destination; compress, compression, force, password, main_redirect = true, arch = target_arch, predicate) do app_stage
        # app_stage always points to app directory
        # app_stage always points to app directory
        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]

        stage(product, MacOS(target_arch), joinpath(app_stage, "Contents/Libraries"); runtime_mode = "SANDBOX", app_name, bundle_identifier)

        install(product.startup_file, joinpath(app_stage, "Contents/Libraries/etc/julia/startup.jl"); parameters = dmg.parameters, force = true)

        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/main.sh")
        install(main_file, joinpath(app_stage, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true, predicate)

        #install_config(joinpath(app_stage, "Contents/Libraries/config"), dmg.parameters)
    end

    return
end

function bundle(product::JuliaAppBundle, snap::Snap, destination::String; compress::Bool = isext(destination, ".snap"), force = false, target_arch = Sys.ARCH)

    predicate = :JULIA_APP_BUNDLE

    bundle(snap, destination; compress, force, predicate) do app_stage

        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]
        
        stage(product, Linux(target_arch), app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)

        install(product.startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = snap.parameters, force = true)
        
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "snap/main.sh")
        app_name = snap.parameters["APP_NAME_LOWERCASE"]
        install(main_file, joinpath(app_stage, "bin/$app_name"); parameters = snap.parameters, executable = true)

        install(snap.configure_hook, joinpath(app_stage, "meta/hooks/configure"); parameters = Dict("PRECOMPILED_MODULES" => join(product.precompiled_modules, ",")), executable = true)

        #install_config(joinpath(app_stage, "config"), snap.parameters)
    end

    return
end

function normalize_executable(path::String)

    tempfile = joinpath(mktempdir(), basename(path))
    mv(path, tempfile)
    cp(tempfile, path)

    return
end

function bundle(product::JuliaAppBundle, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), force = false, target_arch = Sys.ARCH)

    predicate = :JULIA_APP_BUNDLE

    bundle(msix, destination; compress, force, predicate) do app_stage
        
        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]

        stage(product, Windows(target_arch), app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)
        mv("$app_stage/libexec/julia/lld.exe", "$app_stage/bin/lld.exe") # julia.exe can't find shared libraries in UWP

        # Executables extracted from tar archives carry Unix-style metadata that causes 
        # Windows AppX validation to fail with "The parameter is incorrect" when launched 
        # from the Start Menu.
        Sys.iswindows() && normalize_executable("$app_stage/bin/julia.exe")
        
        touch("$app_stage/bin/julia.exe") # updating timestamp to avoid Invalid Parameter error

        install(product.startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = msix.parameters, force = true)
        
        #install_config(joinpath(app_stage, "config"), msix.parameters)

        if msix.windowed
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
    end

    return
end


function bundle(product::JuliaCBundle, dmg::DMG, destination::String; compress::Bool = isext(destination, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), target_arch = Sys.ARCH)

    if !Sys.isapple()
        @warn "The build for the DMG will not work as it is not built on macos"
    end

    if dmg.sandboxed_runtime && !dmg.windowed
        @warn "In hardened runtime mode it is a known bug that GUI terminal won't launch"
    end

    predicate = :JULIAC_BUNDLE
    
    bundle(dmg, destination; compress, compression, force, password, main_redirect = true, arch = target_arch, predicate) do app_stage
        # app_stage always points to app directory
        app_name = dmg.parameters["APP_NAME"]
        bundle_identifier = dmg.parameters["BUNDLE_IDENTIFIER"]

        mkdir(joinpath(app_stage, "Contents/Libraries"))
        stage(product, joinpath(app_stage, "Contents/Libraries"); runtime_mode = "SANDBOX", app_name, bundle_identifier)
        
        # main redirect
        # fixing it may be sufficient here to get the application
        main_file = get_path([joinpath(product.project, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/main.sh")
        install(main_file, joinpath(app_stage, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true, predicate = :JULIAC_BUNDLE)

        #install_config(joinpath(app_stage, "Contents/Libraries/config"), dmg.parameters)
    end

    return
end

function bundle(product::JuliaCBundle, snap::Snap, destination::String; compress::Bool = isext(destination, ".snap"), force = false)

    if !Sys.islinux()
        @warn "The build for the snap will not work as it is not built on linux"
    end

    predicate = :JULIAC_BUNDLE

    bundle(snap, destination; compress, force, install_configure=true, predicate) do app_stage

        app_name = snap.parameters["APP_NAME"]
        bundle_identifier = snap.parameters["BUNDLE_IDENTIFIER"]

        stage(product, app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)

        #install_config(joinpath(app_stage, "config"), snap.parameters)        
    end

    return
end

function bundle(product::JuliaCBundle, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), force = false)

    if !Sys.iswindows()
        @warn "The build for MSIX will not work as it is not built on Windows"
    end
    # I need to pass down the arguments here somehow for the template
    bundle(msix, destination; compress, force, predicate = :JULIAC_BUNDLE) do app_stage

        app_name = msix.parameters["APP_NAME"]
        bundle_identifier = msix.parameters["BUNDLE_IDENTIFIER"]

        stage(product, app_stage; runtime_mode = "SANDBOX", app_name, bundle_identifier)        

        #install_config(joinpath(app_stage, "config"), msix.parameters)

        # May need to look into this
        # if msix.windowed
        #     WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        #     WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        # end
    end

    return
end




"""
    build_app(platform::Windows, source, destination; compress = isext(destination, ".msix"), precompile = true, incremental = true, force = false, windowed = true, adhoc_signing = false)

Build a complete Windows application from Julia source code, optionally packaging it as a MSIX installer.

This function coordinates the entire process of creating a standalone Windows application 
from Julia source code. It handles bundling the application, precompiling code for faster startup, 
code signing, and optionally creating a MSIX installer for distribution. Note that it 
requires a Windows host for precompilation unless `precompile=false` is specified, and the architecture 
of the host must match the target architecture. For code signing, the function uses the 
`WINDOWS_PFX_PASSWORD` environment variable for the certificate password if `meta/msix/certificate.pfx` 
is available, otherwise a one-time self-signing certificate is created for code signing.

The application is expected to have a `main` entry point in the application module (i.e., `MyModule.main([])`).

# Arguments
- `platform::Windows`: Windows platform specification with architecture (e.g., `Windows(:x86_64)`)
- `source::String`: Path to the source directory containing the application's source code and Project.toml
- `destination::String`: Path where the final application directory or MSIX installer should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".msix")`: Whether to create a MSIX installer. Defaults to `true` 
  if destination has .msix extension, otherwise creates an application directory
- `precompile::Bool = true`: Whether to precompile the application code for faster startup
- `incremental::Bool = true`: Whether to perform incremental precompilation (preserving existing compiled files)
- `force::Bool = false`: If `true`, overwrites existing destination
- `windowed::Bool = true`: If `true`, creates a GUI application without console window. Set to `false` for 
  console applications or easier debugging
- `adhoc_signing::Bool = false`: If `true`, skips certificate-based signing (for development/testing only)

# Directory Structure Expectations
The `source` directory is expected to have the following structure:
- `Project.toml`: Contains application metadata and dependencies
- `Manifest.toml`: Dependency lock file
- `src/`: Directory containing application source code with a `main` entry point
- `meta/` (optional): Directory containing customizations
  - `common.jl` (optional): Platform common startup.jl
  - `msix/` (optional): Platform-specific customizations
    - `certificate.pfx` (optional): Code signing certificate
    - `AppxManifest.xml` (optional): Custom MSIX manifest template
    - `resources.pri` (optional): Custom package resource index
    - `MSIXAppInstallerData.xml` (optional): Custom installer configuration
    - `startup.jl` (optional): Platform specific startup.jl

# Examples
```julia
# Build application directory without MSIX packaging
build_app(Windows(:x86_64), source, "MyApp")

# Build a .msix installer
build_app(Windows(:x86_64), source, "MyApp.msix")

# Build console application for debugging
build_app(Windows(:x86_64), source, "MyApp.msix"; windowed = false)

# Build without precompilation (e.g., for cross-compiling)
build_app(Windows(:x86_64), source, "MyApp.msix"; precompile = false)
```
"""
function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), precompile = true, incremental = true, force = false, windowed = true, adhoc_signing = false, sysimg_packages = [], sysimg_args = ``, remove_sources=false)

    msix = MSIX(source; windowed,
                (adhoc_signing ? (; pfx_cert=nothing) : (;))...)

    product = JuliaAppBundle(source; precompile, incremental, sysimg_packages, sysimg_args, remove_sources)
    
    return bundle(product, msix, destination; compress, force, target_arch = arch(platform))
end


"""
    build_app(platform::Linux, source, destination; compress = isext(destination, ".snap"), precompile = true, incremental = true, force = false)

Build a complete Linux application from Julia source code, optionally packaging it as a Snap package.

This function coordinates the entire process of creating a standalone Linux Snap application 
from Julia source code. It handles bundling the application, precompiling code for faster startup, 
and optionally creating a Snap package for distribution. Note that it requires a Linux host for 
precompilation unless `precompile=false` is specified, and the architecture of the host must match 
the target architecture.

The application is expected to have a `main` entry point in the application module (i.e., `MyModule.main([])`).

# Arguments
- `platform::Linux`: Linux platform specification with architecture (e.g., `Linux(:x86_64)`, `Linux(:aarch64)`)
- `source::String`: Path to the source directory containing the application's source code and Project.toml
- `destination::String`: Path where the final application directory or Snap package should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".snap")`: Whether to create a Snap package. Defaults to `true` 
  if destination has .snap extension, otherwise creates an application directory
- `precompile::Bool = true`: Whether to precompile the application code for faster startup
- `incremental::Bool = true`: Whether to perform incremental precompilation (preserving existing compiled files)
- `force::Bool = false`: If `true`, overwrites existing destination

# Directory Structure Expectations
The `source` directory is expected to have the following structure:
- `Project.toml`: Contains application metadata and dependencies
- `Manifest.toml`: Dependency lock file
- `src/`: Directory containing application source code with a `main` entry point
- `meta/` (optional): Directory containing customizations
  - `common.jl` (optional): Platform common startup.jl
  - `snap/` (optional): Platform-specific customizations
    - `icon.png` (optional): Custom application icon
    - `snap.yaml` (optional): Custom Snap metadata template
    - `main.desktop` (optional): Custom desktop entry template
    - `configure.sh` (optional): Custom configuration hook script
    - `startup.jl` (optional): Platform specific startup.jl

# Examples
```julia
# Build application directory without Snap packaging
build_app(Linux(:x86_64), source, "MyApp")

# Build a .snap package
build_app(Linux(:x86_64), source, "MyApp.snap")

# Build for ARM64 architecture
build_app(Linux(:aarch64), source, "MyApp.snap")

# Build without precompilation (e.g., for cross-compiling)
build_app(Linux(:x86_64), source, "MyApp.snap"; precompile = false)
```
"""
function build_app(platform::Linux, source, destination; compress::Bool = isext(destination, ".snap"), precompile = true, incremental = true, force = false, windowed = true, sysimg_packages = [], sysimg_args = ``, remove_sources=false)

    snap = Snap(source; windowed)

    product = JuliaAppBundle(source; precompile, incremental, sysimg_packages, sysimg_args, remove_sources)

    return bundle(product, snap, destination; compress, force, target_arch = arch(platform))
end

"""
    build_app(platform::MacOS, source, destination; compress = isext(destination, ".dmg"), precompile = true, incremental = true, force = false, adhoc_signing = false)

Build a complete macOS application from Julia source code, optionally packaging it as a DMG disk image.

This function coordinates the entire process of creating a standalone macOS application bundle 
from Julia source code. It handles bundling the application, precompiling code for faster startup, 
code signing the bundle, and optionally creating a DMG disk image for distribution. Note that it 
requires a macOS host for precompilation unless `precompile=false` is specified, and the architecture 
of the host must match the target architecture. For code signing, the function uses the 
`MACOS_PFX_PASSWORD` environment variable for the certificate password if `meta/dmg/certificate.pfx` 
is available, otherwise a one-time self-signing certificate is created for code signing.

The application is expected to have a `main` entry point in the application module (i.e., `MyModule.main()`).

# Arguments
- `platform::MacOS`: macOS platform specification with architecture (e.g., `MacOS(:x86_64)`, `MacOS(:arm64)`)
- `source::String`: Path to the source directory containing the application's source code and Project.toml
- `destination::String`: Path where the final application (.app) or disk image (.dmg) should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".dmg")`: Whether to create a DMG disk image. Defaults to `true` 
  if destination has .dmg extension, otherwise creates a .app bundle
- `precompile::Bool = true`: Whether to precompile the application code for faster startup
- `incremental::Bool = true`: Whether to perform incremental precompilation (preserving existing compiled files)
- `force::Bool = false`: If `true`, overwrites existing destination
- `adhoc_signing::Bool = false`: If `true`, skips certificate-based signing (for development/testing only)

# Directory Structure Expectations
The `source` directory is expected to have the following structure:
- `Project.toml`: Contains application metadata and dependencies
- `Manifest.toml`: Dependency lock file
- `src/`: Directory containing application source code with a `main` entry point
- `meta/` (optional): Directory containing customizations
  - `common.jl` (optional): Platform common startup.jl
  - `dmg/` (optional): Platform-specific customizations
    - `certificate.pfx` (optional): Code signing certificate
    - `Entitlements.plist` (optional): Custom entitlements file
    - `Info.plist` (optional): Custom app metadata template
    - `DS_Store` or `DS_Store.toml` (optional): DMG appearance configuration
    - `icon.icns` or `icon.png` (optional): Custom application icon
    - `startup.jl` (optional): Platform specific startup.jl

# Examples
```julia
# Build a .app bundle without DMG packaging
build_app(MacOS(:x86_64), source, "MyApp.app")

# Build a .dmg installer
build_app(MacOS(:aarch64), source, "MyApp.dmg")

# Build without precompilation (e.g., for cross-compiling)
build_app(MacOS(:aarch64), source, "MyApp.dmg"; precompile = false)
```
"""
function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), precompile = true, incremental = true, force = false, windowed = true, adhoc_signing = false, hfsplus = false, sysimg_packages = [], sysimg_args = ``, remove_sources=false)

    dmg = DMG(source; windowed, hfsplus, 
              (adhoc_signing ? (; pfx_cert=nothing) : (;))...)

    product = JuliaAppBundle(source; precompile, incremental, sysimg_packages, sysimg_args, remove_sources)
    
    return bundle(product, dmg, destination; compress, force, target_arch = arch(platform))
end
