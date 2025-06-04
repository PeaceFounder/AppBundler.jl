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
  - `macos/` (optional): Platform-specific customizations
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
function build_app(platform::MacOS, source, destination; compression = isext(destination, ".dmg") ? :lzma : nothing, precompile = true, incremental = true)

    if precompile && (!Sys.isapple() || (Sys.ARCH == "x86_64" && arch(platform) != Sys.ARCH))
        error("Precompilation can only be done on MacOS as currently Julia does not support cross compilation. Set `precompile=false` to make a bundle without precompilation.")
    end

    parameters = get_bundle_parameters("$source/Project.toml")

    build_dmg(source, destination; compression) do app_stage

        bundle_app(platform, source, app_stage; parameters)

        if precompile
            @info "Precompiling"

            if !incremental
                rm("$app_stage/Contents/Libraries/julia/share/julia/compiled", recursive=true)
            end

            julia = "$app_stage/Contents/Libraries/julia/bin/julia"
            #startup = "$app_stage/Contents/Libraries/julia/etc/julia/startup.jl"
            
            # Run the command with the modified environment
            # withenv("JULIA_DEBUG" => "loading") do
            run(`$julia --eval '__precompile__()'`)
            # end
            
        else
            @info "Precompilation disabled. Precompilation will happen on the desitination system at first launch."
        end

        # May not be the only ones
        run(`find $app_stage -name "._*" -delete`)
    end

    return 
end


"""
    build_dmg(setup::Function, source, destination; compression = isext(destination, ".dmg") ? :lzma : nothing)

Create a macOS application bundle or DMG disk image with automatic code signing and customizable setup.

This function provides a flexible way to create macOS applications by accepting a custom setup function 
that defines how the application should be prepared. It handles staging directory management, 
code signing with certificates or self-signing, and optionally packages the result into a 
distributable DMG installer with custom appearance settings.

# Arguments
- `setup::Function`: A function that takes the staging directory path as an argument and performs 
  the necessary application setup (typically called from `build_app` to bundle the Julia application)
- `source::String`: Path to the source directory containing the application's source code and Project.toml
- `destination::String`: Path where the final .app bundle or .dmg disk image should be created

# Keyword Arguments
- `compression = nothing|:lzma|:bzip2|:zlib|:lzfse`: Compression algorithm for DMG creation. Defaults to `:lzma` for .dmg destinations, `nothing` creates standalone .app bundles.

# Code Signing

The function automatically handles code signing for all created applications. If a signing certificate is available at `meta/macos/certificate.pfx`, it will be used along with the password from the `MACOS_PFX_PASSWORD` environment variable. When no certificate file is present, the function generates and uses a temporary self-signed certificate for signing.

Custom entitlements can be specified by placing an `Entitlements.plist` file in `meta/macos/`. If this file is not found, default entitlements appropriate for most applications will be used automatically.

# Directory Structure Requirements
Expects the following optional customization files in the source directory:
- `meta/macos/certificate.pfx`: Code signing certificate (optional)
- `meta/macos/Entitlements.plist`: Custom entitlements (optional, uses default if not found)  
- `meta/macos/DS_Store`: Direct DMG appearance file (optional)
- `meta/macos/DS_Store.toml`: DMG appearance template (optional, uses default if not found)

# Examples
```julia
build_dmg("src/", "MyApp.dmg"; compression = :lzma) do staging_dir
    bundle_app(MacOS(:arm64), "src/", staging_dir)
    # Perform any additional customizations
end
```
"""
function build_dmg(setup::Function, source, destination; compression = isext(destination, ".dmg") ? :lzma : nothing)

    parameters = get_bundle_parameters("$source/Project.toml")
    appname = parameters["APP_NAME"]
    
    #staging_dir = isnothing(compression) ? dirname(destination) : joinpath(tempdir(), appname) 
    app_stage = !isnothing(compression) ? joinpath(tempdir(), "$appname/$appname.app") : destination
    
    rm(app_stage; force=true, recursive=true)
    rm(destination; force=true)

    mkpath(app_stage)
    
    setup(app_stage)
    bundle_dmg(source, app_stage; parameters)

    password = get(ENV, "MACOS_PFX_PASSWORD", "")

    pfx_path = joinpath(source, "meta", "macos", "certificate.pfx")
    if !isfile(pfx_path)
        pfx_path = nothing
    end

    entitlements_path = joinpath(source, "meta/macos/Entitlements.plist")
    if isfile(entitlements_path)
        @info "Using entitlements $entitlements_path"
    else
        @info "No override found at $entitlements_path; using default override"
        entitlements_path = joinpath(dirname(@__DIR__), "recipes/macos/Entitlements.plist")
    end

    installer_title = join([parameters["APP_DISPLAY_NAME"], "Installer"], " ")

    direct_override = joinpath(source, "meta/macos/DS_Store")
    if isfile(direct_override)
        dsstore = direct_override
    else

        dsstore_toml_template = joinpath(source, "meta/macos/DS_Store.toml")
        if !isfile(dsstore_toml_template)
            dsstore_toml_template = joinpath(dirname(@__DIR__), "recipes/macos/DS_Store.toml")
        end

        dsstore_toml = Mustache.render(String(read(dsstore_toml_template)), parameters)
        dsstore = TOML.parse(dsstore_toml)
    end    
    
    DMGPack.pack2dmg(app_stage, destination, entitlements_path; pfx_path, dsstore, password, compression, installer_title)
    
    return
end


function build_app(platform::Linux, source, destination; compress::Bool = isext(destination, ".snap"))

    rm(destination, recursive=true, force=true)

    if compress
        app_dir = joinpath(tempdir(), splitext(basename(destination))[1])
        rm(app_dir, recursive=true, force=true)
    else
        app_dir = destination 
    end
    mkpath(app_dir)

    @info "Bundling the application"

    bundle_app(platform, source, app_dir)
    
    # ToDo: refactor precompilation

    if compress
        @info "Squashing into a snap archive"
        SnapPack.pack2snap(app_dir, destination)
        rm(app_dir, recursive=true, force=true)
    end

    return
end


"""
    build_msix(setup::Function, source::String, destination::String; compress::Bool = isext(destination, ".msix"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, parameters = get_bundle_parameters("\$source/Project.toml"))

This function creates a Windows MSIX installer by first running a setup function to prepare 
the application staging directory, then bundling the MSIX metadata and structure, and finally 
optionally compressing it into a distributable MSIX package with code signing.

# Arguments
- `setup::Function`: A function that takes the staging directory path as an argument and performs 
  the necessary setup (typically bundling the Julia application and its dependencies)
- `source::String`: Path to the source directory containing the application's source code, Project.toml, and main.jl
- `destination::String`: Path where the final application directory or MSIX package should be created

# Keyword Arguments
- `compress::Bool = isext(destination, ".msix")`: Whether to compress the application into an MSIX package.
  Defaults to `true` if the destination has a .msix extension, otherwise `false` (creates directory structure only)
- `path_length_threshold::Int = 260`: Maximum allowed path length for files in the MSIX package.
  Files with paths exceeding this length will be handled according to `skip_long_paths`
- `skip_long_paths::Bool = false`: Whether to skip files with paths longer than `path_length_threshold`.
  If `false`, an error will be thrown for long paths
- `parameters = get_bundle_parameters("\$source/Project.toml")`: Dictionary containing application parameters
  extracted from Project.toml, used for MSIX manifest generation

# Directory Structure Expectations
The `source` directory should contain:
- `Project.toml`: Application metadata and dependencies
- `main.jl`: Application entry point
- `meta/windows/` (optional): Windows-specific customizations
  - `certificate.pfx` (optional): Code signing certificate (password from `WINDOWS_PFX_PASSWORD` env var)
  - `AppxManifest.xml` (optional): Custom MSIX application manifest
  - `resources.pri` (optional): Custom application resource file
  - `MSIXAppInstallerData.xml` (optional): Installer configuration

# Code Signing

Codesigning is performed automatically if `compress=true`. The codesigning certificate is specified with `meta/windows/certificate.pfx` that is password encrypted that is passed with `WINDOWS_PFX_PASSWORD` environment variable. If signing certificate is not available a temporary one time self-signed certificate is generated and used for signing the MSIX installer.

# Examples
```julia
# Used internally by build_app for Windows
build_msix("src/", "MyApp.msix") do staging_dir
    # Setup function: bundle Julia app into staging_dir
    bundle_app(Windows(:x86_64), "src/", staging_dir)
end

# Create directory structure without MSIX compression
build_msix("src/", "MyApp/") do staging_dir
    bundle_app(Windows(:x86_64), "src/", staging_dir)
end
```
"""
function build_msix(setup::Function, source::String, destination::String; compress::Bool = isext(destination, ".msix"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, parameters = get_bundle_parameters("$source/Project.toml"))

    rm(destination; force=true)

    if compress
        app_stage = joinpath(tempdir(), "msixapp")
        rm(app_stage; force=true, recursive=true)
    else
        app_stage = destination
    end

    mkdir(app_stage)
    
    setup(app_stage)

    bundle_msix(source, app_stage; parameters)

    if compress
        
        password = get(ENV, "WINDOWS_PFX_PASSWORD", "")

        pfx_path = joinpath(source, "meta", "windows", "certificate.pfx")
        if !isfile(pfx_path)
            pfx_path = nothing
        end

        MSIXPack.pack2msix(app_stage, destination; pfx_path, password, path_length_threshold, skip_long_paths)        
        
    end    
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
function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, debug::Bool = false, precompile = true, incremental = true) 

    if precompile && (!Sys.iswindows() || !(Sys.ARCH == arch(platform)))
        error("Precompilation can only be done on Windows as currently Julia does not support cross compilation. Set `precompile=false` to make a bundle without precompilation.")
    end

    parameters = get_bundle_parameters("$source/Project.toml")

    build_msix(source, destination; compress, path_length_threshold, skip_long_paths, parameters) do app_stage

        @info "Bundling application dependencies"
        bundle_app(platform, source, app_stage; parameters)

        if precompile
            @info "Precompiling"

            if !incremental
                rm("$app_stage/julia/share/julia/compiled", recursive=true)
            end

            julia = "$app_stage/julia/bin/julia.exe"
            run(`$julia --eval '__precompile__()'`)
        else
            @info "Precompilation disabled. Precompilation will happen on the desitination system at first launch."
        end

        if !debug
            WinSubsystem.change_subsystem_inplace("$app_stage/julia/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/julia/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end

    end

end
