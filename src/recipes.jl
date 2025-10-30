using Base.BinaryPlatforms: arch
using Pkg.BinaryPlatforms: Linux, Windows, MacOS
using .Stage: stage, PkgImage

function bundle(product::PkgImage, dmg::DMG, destination::String; compress::Bool = isext(dest, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), arch = :x86_64)
    
    bundle(dmg, destination; compress, compression, force, password, main_redirect = true, arch) do app_stage
        # app_stage always points to app directory
        stage(product, MacOS(arch), joinpath(app_stage, "Contents/Libraries"))

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/startup.jl")
        install(startup_file, joinpath(app_stage, "Contents/Libraries/etc/julia/startup.jl"); parameters = dmg.parameters, force = true)

        common_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "common.jl")
        install(common_file, joinpath(app_stage, "Contents/Libraries/etc/julia/common.jl"); parameters = dmg.parameters)

        # main redirect
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/main.sh")
        install(main_file, joinpath(app_stage, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true)
        
    end

    return
end

function bundle(product::PkgImage, snap::Snap, destination::String; compress::Bool = isext(dest, ".snap"), force = false, arch = :x86_64)

    snap.parameters["PRECOMPILED_MODULES"] = join(product.precompiled_modules, ", ")
    
    bundle(snap, destination; compress, force, install_configure = true) do app_stage
        
        stage(product, Linux(arch), app_stage)

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "snap/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = snap.parameters, force = true)

        common_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "common.jl")
        install(common_file, joinpath(app_stage, "etc/julia/common.jl"); parameters = snap.parameters)
        
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "snap/main.sh")
        app_name = snap.parameters["APP_NAME_LOWERCASE"]
        install(main_file, joinpath(app_stage, "bin/$app_name"); parameters = snap.parameters, executable = true)

    end

    return
end

function normalize_executable(path::String)

    tempfile = joinpath(mktempdir(), basename(path))
    mv(path, tempfile)
    cp(tempfile, path)

    return
end

function bundle(product::PkgImage, msix::MSIX, destination::String; compress::Bool = isext(dest, ".msix"), force = false, arch = :x86_64)

    bundle(msix, destination; compress, force) do app_stage
        
        stage(product, Windows(arch), app_stage)
        mv("$app_stage/libexec/julia/lld.exe", "$app_stage/bin/lld.exe") # julia.exe can't find shared libraries in UWP

        # Executables extracted from tar archives carry Unix-style metadata that causes 
        # Windows AppX validation to fail with "The parameter is incorrect" when launched 
        # from the Start Menu.
        Sys.iswindows() && normalize_executable("$app_stage/bin/julia.exe")
        
        touch("$app_stage/bin/julia.exe") # updating timestamp to avoid Invalid Parameter error

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "msix/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = msix.parameters, force = true)

        common_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "common.jl")
        install(common_file, joinpath(app_stage, "etc/julia/common.jl"); parameters = msix.parameters)
        
        if msix.windowed
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
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
function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), precompile = true, incremental = true, force = false, windowed = true, adhoc_signing = false)

    if adhoc_signing
        msix = MSIX(source; windowed, pfx_cert=nothing)
    else
        msix = MSIX(source; windowed)
    end

    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, msix, destination; compress, force, arch = arch(platform))
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
function build_app(platform::Linux, source, destination; compress::Bool = isext(destination, ".snap"), precompile = true, incremental = true, force = false, windowed = true)

    snap = Snap(source; windowed)
    product = PkgImage(source; precompile, incremental)

    return bundle(product, snap, destination; compress, force, arch = arch(platform))
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
function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), precompile = true, incremental = true, force = false, windowed = true, adhoc_signing = false)

    if adhoc_signing
        dmg = DMG(source; windowed, pfx_cert=nothing)
    else
        dmg = DMG(source; windowed)
    end

    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, dmg, destination; compress, force, arch = arch(platform))
end
