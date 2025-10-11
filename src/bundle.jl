import TOML

import Pkg, Artifacts
using Pkg.BinaryPlatforms: MacOS
using AppBundlerUtils_jll
import Mustache

function get_bundle_parameters(project_toml)

    toml_dict = TOML.parsefile(project_toml)

    parameters = Dict{String, Any}()

    parameters["MODULE_NAME"] = get(toml_dict, "name", "MainEntry")

    app_name = haskey(toml_dict, "APP_NAME") ? toml_dict["APP_NAME"] : haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))
    parameters["APP_NAME"] = lowercase(join(split(app_name, " "), "-"))
    #parameters["APP_DIR_NAME"] = haskey(toml_dict, "name") ? toml_dict["name"] : basename(dirname(project_toml))
    parameters["APP_VERSION"] = haskey(toml_dict, "version") ? toml_dict["version"] : "0.0.1"

    # Setting defaults
    parameters["APP_DISPLAY_NAME"] = app_name #parameters["APP_NAME"]
    parameters["APP_SUMMARY"] = "This is a default app summary"
    parameters["APP_DESCRIPTION"] = "A longer description of the app"
    parameters["WITH_SPLASH_SCREEN"] = "false"
    parameters["BUNDLE_IDENTIFIER"] = "org.appbundler." * lowercase(parameters["APP_NAME"])
    parameters["PUBLISHER"] = "CN=AppBundler"
    parameters["PUBLISHER_DISPLAY_NAME"] = "AppBundler"
    parameters["BUILD_NUMBER"] = 0
    
    if haskey(toml_dict, "bundle")
        for (key, value) in toml_dict["bundle"]
            parameters[key] = string(value) # Mustache does not print false.
        end
    end

    parameters["APP_NAME_LOWERCASE"] = lowercase(parameters["APP_NAME"])

    return parameters
end

struct MSIX
    icon::String # direcotry reading is something to look into here
    appxmanifest::String 
    msixinstallerdata::String 
    resources_pri::String
    path_length_threshold::Int 
    skip_long_paths::Bool 
    pfx_cert::Union{String, Nothing} 
    parameters::Dict
end

function MSIX(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              icon = get_path(prefix, ["msix/Assets", "msix/icon.png", "icon.png"]; dir = true),
              appxmanifest = get_path(prefix, "msix/AppxManifest.xml"),
              resources_pri = get_path(prefix, "msix/resources.pri"),
              msixinstallerdata = get_path(prefix, "msix/MSIXAppInstallerData.xml"),
              path_length_threshold = 260,
              skip_long_paths = false,
              pfx_cert = get_path(prefix, "msix/certificate.pfx"), # We actually want the warning
              parameters = Dict()
              )
    
    return MSIX(icon, appxmanifest, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, pfx_cert, parameters)
end

function MSIX(overlay; kwargs...)
    
    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]

    # ToDo: refactor setting of the defaults
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return MSIX(; prefix, parameters, kwargs...)
end


struct Snap # by extensions files could have multiple modes that are set via stage command
    icon::String
    snap_config::String
    desktop_launcher::String
    configure_hook::String # needs to be enabled when staging
    parameters::Dict
end

function Snap(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              icon = get_path(prefix, ["snap/icon.png", "icon.png"]),
              snap_config = get_path(prefix, "snap/snap.yaml"),
              desktop_launcher = get_path(prefix, "snap/main.desktop"),
              configure_hook = get_path(prefix, "snap/configure.sh"),
              parameters = Dict()
              )

    return Snap(icon, snap_config, desktop_launcher, configure_hook, parameters)
end

function Snap(overlay; kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return Snap(; prefix, parameters, kwargs...)
end

struct DMG
    icon::String
    info_config::String
    entitlements::String
    dsstore::String # if it's toml then use it as source for parsing
    pfx_cert::Union{String, Nothing}
    #notary::Nothing
    parameters::Dict
end

# soft link can be used in case one needs to use png source. The issue here is of communicating intent.
function DMG(;
             prefix = joinpath(dirname(@__DIR__), "recipes"),
             icon = get_path(prefix, ["dmg/icon.icns", "dmg/icon.png", "icon.icns"]),
             info_config = get_path(prefix, "dmg/Info.plist"),
             entitlements = get_path(prefix, "dmg/Entitlements.plist"),
             dsstore = get_path(prefix, ["dmg/DS_Store.toml", "dmg/DS_Store"]),
             pfx_cert = get_path(prefix, "dmg/certificate.pfx"),
             parameters = Dict()
             )

    return DMG(icon, info_config, entitlements, dsstore, pfx_cert, parameters)
end

function DMG(overlay; kwargs...)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return DMG(; prefix, parameters, kwargs...)
end

function stage(msix::MSIX, destination::String)

    if !isdir(destination)
        mkdir(destination)
    end

    if isdir(msix.icon)
        @info "Treating icon path as assets directory"
        #install(msix.icon, joinpath(destination, "Assets"))
        cp(msix.icon, joinpath(destination, "Assets"))
    else
        MSIXIcons.generate_app_icons(msix.icon, joinpath(destination, "Assets")) 
    end

    (; parameters) = msix
    install(msix.appxmanifest, joinpath(destination, "AppxManifest.xml"); parameters)
    cp(msix.resources_pri, joinpath(destination, "resources.pri"))
    install(msix.msixinstallerdata, joinpath(destination, "Msix.AppInstaller.Data/MSIXAppInstallerData.xml"); parameters)

    return
end

function install_dsstore(source::String, dsstore_destination::String; parameters = Dict())

    rm(dsstore_destination; force=true)

    if last(splitext(source)) == ".toml"

        dsstore_toml = Mustache.render(read(source, String), parameters)
        dsstore = TOML.parse(dsstore_toml)

        DSStore.open_dsstore(dsstore_destination, "w+") do ds

            ds[".", "icvl"] = ("type", "icnv")
            ds[".", "vSrn"] = ("long", 1)

            for file_key in keys(dsstore)
                file_dict = dsstore[file_key]
                for entry_key in keys(file_dict)
                    ds[file_key, entry_key] = file_dict[entry_key]
                end
            end
        end
        
    else
        cp(source, dsstore_destination)
    end

    return
end

function retrieve_macos_launcher(platform::MacOS)

    artifacts_toml = joinpath(dirname(dirname(pathof(AppBundlerUtils_jll))), "Artifacts.toml")
    artifacts = Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]

    try 

        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = artifacts_cache()

        hash = artifacts["git-tree-sha1"]
        Pkg.Artifacts.ensure_artifact_installed("AppBundlerUtils", artifacts, artifacts_toml) 

        return joinpath(artifacts_cache(), hash, "bin", "macos_launcher")

    finally
        Artifacts.ARTIFACTS_DIR_OVERRIDE[] = nothing
    end

    return
end

# main redirect is an option one can opt in during the staging
function stage(dmg::DMG, destination::String; dsstore = false, main_redirect = false, arch = :x86_64) # destination folder is used as appdir

    (; parameters) = dmg
    app_name = parameters["APP_NAME"]

    install(dmg.icon, joinpath(destination, "Contents/Resources/icon.icns"))
    install(dmg.info_config, joinpath(destination, "Contents/Info.plist"); parameters)

    if main_redirect
        launcher = retrieve_macos_launcher(MacOS(arch))
        install(launcher, joinpath(destination, "Contents/MacOS/$app_name"); executable = true)
    end

    if dsstore
        symlink("/Applications", joinpath(dirname(destination), "Applications"); dir_target=true)
        install_dsstore(dmg.dsstore, joinpath(dirname(destination), ".DS_Store"); parameters)
    end

    return
end

function stage(snap::Snap, destination::String; install_configure = false)

    (; parameters) = snap
    app_name = parameters["APP_NAME_LOWERCASE"]

    install(snap.icon, joinpath(destination, "meta/icon.png"))
    install(snap.snap_config, joinpath(destination, "meta/snap.yaml"); parameters)
    install(snap.desktop_launcher, joinpath(destination, "meta/gui/$app_name.desktop"); parameters)
    
    if install_configure
        install(snap.configure_hook, joinpath(destination, "meta/hooks/configure"); parameters, executable = true)
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
function bundle(setup::Function, dmg::DMG, destination::String; compress::Bool = isext(destination, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), main_redirect = false, arch = :x86_64) 

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    if compress
        appname = dmg.parameters["APP_NAME"]
        app_stage = joinpath(mktempdir(), "$appname.app")
        stage(dmg, app_stage; dsstore = true, main_redirect, arch)        
    else
        app_stage = destination
        stage(dmg, app_stage; dsstore = false, main_redirect, arch)        
    end

    setup(app_stage)
    
    installer_title = join([dmg.parameters["APP_DISPLAY_NAME"], "Installer"], " ")

    DMGPack.pack(app_stage, destination, dmg.entitlements; pfx_path = dmg.pfx_cert, password, compression = compress ? compression : nothing, installer_title)

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
- `meta/msix/` (optional): Windows-specific customizations
  - `certificate.pfx` (optional): Code signing certificate (password from `WINDOWS_PFX_PASSWORD` env var)
  - `AppxManifest.xml` (optional): Custom MSIX application manifest
  - `resources.pri` (optional): Custom application resource file
  - `MSIXAppInstallerData.xml` (optional): Installer configuration

# Code Signing

Codesigning is performed automatically if `compress=true`. The codesigning certificate is specified with `meta/msix/certificate.pfx` that is password encrypted that is passed with `WINDOWS_PFX_PASSWORD` environment variable. If signing certificate is not available a temporary one time self-signed certificate is generated and used for signing the MSIX installer.

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
function bundle(setup::Function, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), force = false, password = get(ENV, "WINDOWS_PFX_PASSWORD", ""))

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = compress ? mktempdir() : destination

    stage(msix, app_stage)    
    setup(app_stage)

    # ToDo: move path_length_threshold and skip_long_paths checks here
    (; path_length_threshold, skip_long_paths) = msix
    Sys.iswindows() || ensure_windows_compatability(app_stage; path_length_threshold, skip_long_paths)

    if compress
        (; path_length_threshold, skip_long_paths) = msix
        MSIXPack.pack(app_stage, destination; pfx_path = msix.pfx_cert, password)        
    end
    
    return
end

function bundle(setup::Function, snap::Snap, destination::String; compress::Bool = isext(destination, ".snap"), force = false, install_configure = false)

    if ispath(destination)
        if force
            rm(destination; force=true, recursive=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = compress ? mktempdir() : destination
    chmod(app_stage, 0o755)

    stage(snap, app_stage; install_configure)    
    setup(app_stage)

    if compress
        SnapPack.pack(app_stage, destination)
    end

    return
end
