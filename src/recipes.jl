using Base.BinaryPlatforms: arch
using Pkg.BinaryPlatforms: Linux, Windows, MacOS
using .Stage: stage, PkgImage

function bundle(product::PkgImage, dmg::DMG, destination::String; compress::Bool = isext(dest, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), arch = :x86_64)
    
    bundle(dmg, destination; compress, compression, force, password, main_redirect = true, arch) do app_stage
        # app_stage always points to app directory
        stage(product, MacOS(arch), joinpath(app_stage, "Contents/Libraries"))

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/startup.jl")
        install(startup_file, joinpath(app_stage, "Contents/Libraries/etc/julia/startup.jl"); parameters = dmg.parameters, force = true)

        # main redirect
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "dmg/main.sh")
        install(main_file, joinpath(app_stage, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true)
        
    end

    return
end

function bundle(product::PkgImage, snap::Snap, destination::String; compress::Bool = isext(dest, ".snap"), force = false, arch = :x86_64)
    
    bundle(snap, destination; compress, force, install_configure = true) do app_stage
        
        stage(product, Linux(arch), app_stage)

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "snap/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = snap.parameters, force = true)
        
        
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "snap/main.sh")
        app_name = snap.parameters["APP_NAME_LOWERCASE"]
        install(main_file, joinpath(app_stage, "bin/$app_name"); parameters = snap.parameters, executable = true)

    end

    return
end

function bundle(product::PkgImage, msix::MSIX, destination::String; compress::Bool = isext(dest, ".msix"), force = false, arch = :x86_64, windowed = true)

    bundle(msix, destination; compress, force) do app_stage
        
        stage(product, Windows(arch), app_stage)
        mv("$app_stage/libexec/julia/lld.exe", "$app_stage/bin/lld.exe") # julia.exe can't find shared libraries in UWP
        
        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "msix/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = msix.parameters, force = true)
        
        if windowed
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
    end

    return
end

"""
    build_app(platform::Windows, source, destination; debug = false, precompile = true, incremental = true)

Build a complete Windows application from Julia source code, optionally packaging it as a MSIX disk image.

This function coordinates the entire process of creating a standalone MSIX application bundle 
from Julia source code. It handles bundling the application, precompiling code for faster startup, 
code signing the bundle, and optionally creating a MSIX for distribution. Note that it 
requires a Windows host for precompilation unless `precompile=false` is specified, and the architecture 
of the host must match the target architecture. For code signing, the function uses the 
`WINDOWS_PFX_PASSWORD` environment variable for the certificate password if `meta/windows/certificate.pfx` is available otherwise one time self signing certificate is created for the codesigning.

# Arguments
- `platform::Windows`: Windows platform specification, potentially including architecture information
- `source::String`: Path to the source directory containing the application's source code, Project.toml, and main.jl
- `destination::String`: Path where the final application directory or MSIX installer should be created

# Keyword Arguments
- `debug::Bool = false`: Creates application by keeping subsystem as console app for easier debugging. 
- `precompile::Bool = true`: Whether to precompile the application code for faster startup
- `incremental::Bool = true`: Whether to perform incremental precompilation (preserving existing compiled files)

# Directory Structure Expectations
The `source` directory is expected to have the following structure:
- `Project.toml`: Contains application metadata and dependencies
- `main.jl`: The application's entry point script
- `src/` (optional): Directory containing application source code
- `meta/` (optional): Directory containing customizations
  - `windows/` (optional): Platform-specific customizations
    - `certificate.pfx` (optional): Code signing certificate
    - `AppxManifest.xml` (optional): Custom application specification file
    - `resources.pri` (optional): Custom asset resource file
    - `MSIXAppInstallerData.xml` (optional): installer customization
    - `startup.jl` (optional): app launcher customization

# Examples
```julia
# Build aapplication directoruy bundle without MSIX packaging
build_app(MacOS(:x86_64), "path/to/source", "path/to/MyApp")

# Build a .msix installer
build_app(Windows(:x86_64), "path/to/source", "path/to/MyApp.msix")

# Build without precompilation (e.g., for cross-compiling)
build_app(Windows(:x86_64), "path/to/source", "path/to/MyApp.msix"; precompile = false)
"""
function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), precompile = true, incremental = true, force = false, windowed = true)

    msix = MSIX(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, msix, destination; compress, force, windowed, arch = arch(platform))
end

# For some reaseon I did not have documentation here
function build_app(platform::Linux, source, destination; compress::Bool = isext(destination, ".snap"), precompile = true, incremental = true, force = false)

    snap = Snap(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, snap, destination; compress, force, arch = arch(platform))
end

"""
    build_app(platform::MacOS, source, destination; compression = :lzma, precompile = true, incremental = true)

Build a complete macOS application from Julia source code, optionally packaging it as a DMG disk image.

This function coordinates the entire process of creating a standalone macOS application bundle 
from Julia source code. It handles bundling the application, precompiling code for faster startup, 
code signing the bundle, and optionally creating a DMG disk image for distribution. Note that it 
requires a macOS host for precompilation unless `precompile=false` is specified, and the architecture 
of the host must match the target architecture. For code signing, the function uses the 
`MACOS_PFX_PASSWORD` environment variable for the certificate password if `meta/macos/certificate.pfx` is available otherwise one time self signing certificate is created for the codesigning.

# Arguments
- `platform::MacOS`: macOS platform specification, potentially including architecture information
- `source::String`: Path to the source directory containing the application's source code, Project.toml, and main.jl
- `destination::String`: Path where the final application (.app) or disk image (.dmg) should be created

# Keyword Arguments
- `compression::Union{Symbol, Nothing} = :lzma`: Compression algorithm 
  to use for the DMG. Options are `:lzma`, `:bzip2`, `:zlib`, `:lzfse`, or `nothing` for no compression.
  Defaults to `:lzma` if destination has a .dmg extension, otherwise `nothing` that creates an `.app` as final product 
- `precompile::Bool = true`: Whether to precompile the application code for faster startup
- `incremental::Bool = true`: Whether to perform incremental precompilation (preserving existing compiled files)

# Directory Structure Expectations
The `source` directory is expected to have the following structure:
- `Project.toml`: Contains application metadata and dependencies
- `main.jl`: The application's entry point script
- `src/` (optional): Directory containing application source code
- `meta/` (optional): Directory containing customizations
  - `dmg/` (optional): Platform-specific customizations
    - `certificate.pfx` (optional): Code signing certificate
    - `Entitlements.plist` (optional): Custom entitlements file
    - `DS_Store` or `DS_Store.toml` (optional): DMG appearance configuration
    - `startup.jl` (optional): app launcher customization
    - Other template overrides (optional): Custom versions of template files (see `bundle_app` docstring)

# Examples
```julia
# Build a .app bundle without DMG packaging
build_app(MacOS(:x86_64), "path/to/source", "path/to/MyApp.app")

# Build a .dmg installer with LZMA compression
build_app(MacOS(:arm64), "path/to/source", "path/to/MyApp.dmg")

# Build without precompilation (e.g., for cross-compiling)
build_app(MacOS(:arm64), "path/to/source", "path/to/MyApp.dmg"; precompile = false)
"""
function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), precompile = true, incremental = true, force = false)

    dmg = DMG(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, dmg, destination; compress, force, arch = arch(platform))
end

