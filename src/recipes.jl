"""
    bundle_app(platform::MacOS, source, destination; parameters)

Bundle a Julia application into a macOS .app bundle structure.

This function transforms Julia source code into a macOS application bundle (.app), creating the proper directory hierarchy and configuration files required by macOS. It sets up a complete standalone application that can be distributed and run on macOS without requiring a separate Julia installation. The function handles all aspects of the bundling process, including embedding the Julia runtime, copying application code, retrieving necessary packages and artifacts, and creating the required metadata files.

The source directory is expected to contain a `main.jl` file, which serves as the entry point to the application. This file will be executed when the application is launched. The function also expects the source directory to have a valid `Project.toml` file from which it extracts application metadata.

The function uses a template-based approach for creating the bundle structure. Template files such as `Info.plist`, launcher scripts, and other resources are sourced from the `AppBundler/recipes/macos` directory by default. These templates can be customized by providing overrides in a `meta/macos` directory within the source directory. This allows for application-specific customization of the bundle while maintaining a standard structure.

# Arguments
- `platform::MacOS`: MacOS platform specification, including architecture information and a target Julia version
- `source::String`: Path to the source directory containing the application's source code, Project.toml, and `main.jl`
- `destination::String`: Path where the .app bundle should be created

# Keyword Arguments
- `parameters::Dict = get_bundle_parameters("\$source/Project.toml")`: Application parameters extracted 
  from Project.toml, including app name, display name, version, and other metadata

# Notes
- Creates a standard macOS .app bundle with structure:
  - `Contents/`: Main bundle contents
    - `MacOS/`: Contains the executable launcher
    - `Resources/`: Application resources and icons
    - `Libraries/`: Includes Julia runtime, application module code, packages, and artifacts
    - `Info.plist`: Bundle configuration

This function is typically called by the higher-level `build_app` function which handles additional operations like code signing, precompilation, and DMG packaging
"""
function bundle_app(platform::MacOS, source, destination; with_splash_screen = nothing, parameters = get_bundle_parameters("$source/Project.toml"))

    rm(destination, recursive=true, force=true)

    app_name = parameters["APP_NAME"]
    module_name = parameters["MODULE_NAME"]

    if isnothing(with_splash_screen) 
        with_splash_screen = parse(Bool, parameters["WITH_SPLASH_SCREEN"]) # When not set take a value 
    else
        parameters["WITH_SPLASH_SCREEN"] = with_splash_screen
    end

    rm(joinpath(destination), recursive=true, force=true)
    mkpath(destination)
    app_dir = "$destination/Contents"

    bundle = Bundle(joinpath(dirname(@__DIR__), "recipes"), joinpath(source, "meta"))
    
    add_rule!(bundle, "macos/Resources", "Resources")
    add_rule!(bundle, "icon.icns", "Resources/icon.icns")
    
    add_rule!(bundle, "startup", "Libraries/startup")

    add_rule!(bundle, "macos/main.sh", "Libraries/main", template=true, executable=true)
    add_rule!(bundle, "macos/Info.plist", "Info.plist", template=true)

    mkpath("$app_dir/Libraries")
    copy_app(source, "$app_dir/Libraries/$module_name")
    retrieve_julia(platform, "$app_dir/Libraries/julia")

    add_rule!(bundle, "macos/startup.jl", "Libraries/julia/etc/julia/startup.jl", template=true, override=true)
    
    build(bundle, app_dir, parameters)

    retrieve_packages(source, "$app_dir/Libraries/packages"; with_splash_screen)
    retrieve_artifacts(platform, "$app_dir/Libraries/packages", "$app_dir/Libraries/artifacts")

    mkdir(joinpath(destination, "Contents/MacOS"))
    retrieve_macos_launcher(platform, joinpath(destination, "Contents/MacOS/$app_name"))

    return
end

function bundle_app(platform::Linux, source, app_dir)

    rm(app_dir, recursive=true, force=true)

    # This may not be DRY enough
    parameters = get_bundle_parameters("$source/Project.toml")
    parameters["APP_NAME"] = lowercase(parameters["APP_NAME"]) # necessary for a snap name
    app_name = parameters["APP_NAME"]
    parameters["ARCH_TRIPLET"] = linux_arch_triplet(arch(platform))

    # if compress
    #     app_dir = joinpath(tempdir(), basename(destination)[1:end-4])
    #     rm(app_dir, recursive=true, force=true)
    # else
    #     app_dir = destination 
    # end
    # mkpath(app_dir)

    bundle = Bundle(joinpath(dirname(@__DIR__), "recipes"), joinpath(source, "meta"))

    add_rule!(bundle, "precompile.jl", "lib/startup/precompile.jl")
    add_rule!(bundle, "startup", "lib/startup") 
    add_rule!(bundle, "linux/wayland-launch.sh", "bin/wayland-launch", template=true, executable=true) 
    add_rule!(bundle, "linux/main.sh", "bin/$app_name", template=true, executable=true)
    add_rule!(bundle, "linux/precompile.sh", "bin/precompile", template=true, executable=true)

    add_rule!(bundle, "linux/configure.sh", "meta/hooks/configure", template=true, executable=true)
    add_rule!(bundle, "linux/main.desktop", "meta/gui/$app_name.desktop", template=true)
    add_rule!(bundle, "linux/snap.yaml", "meta/snap.yaml", template=true)

    add_rule!(bundle, "linux/meta", "meta")
    add_rule!(bundle, "icon.png", "meta/icon.png") 

    build(bundle, app_dir, parameters)

    retrieve_julia(platform, "$app_dir/lib/julia")    
    copy_app(source, "$app_dir/lib/$app_name")
    retrieve_packages(source, "$app_dir/lib/packages")
    retrieve_artifacts(platform, "$app_dir/lib/packages", "$app_dir/lib/artifacts")

    return
end

function bundle_app(platform::Windows, source, destination; parameters = get_bundle_parameters("$source/Project.toml"))

    app_name = parameters["APP_NAME"]

    retrieve_julia(platform, "$destination/julia")
    mv("$destination/julia/libexec/julia/lld.exe", "$destination/julia/bin/lld.exe") # julia.exe can't find shared libraries in UWP

    retrieve_packages(source, "$destination/packages")
    retrieve_artifacts(platform, "$destination/packages", "$destination/artifacts")

    copy_app(source, "$destination/$app_name")

    bundle = Bundle(joinpath(dirname(@__DIR__), "recipes"), joinpath(source, "meta"))
    add_rule!(bundle, "windows/startup.jl", "julia/etc/julia/startup.jl", template=true, override=true)
    build(bundle, destination, parameters)

end

function bundle_msix(source, destination; debug::Bool = false, parameters = get_bundle_parameters("$source/Project.toml"))

    bundle = Bundle(joinpath(dirname(@__DIR__), "recipes"), joinpath(source, "meta"))

    add_rule!(bundle, "startup", "startup") 
    add_rule!(bundle, "windows/Assets", "Assets") # This shall overwrite destination if it is present
    add_rule!(bundle, "windows/AppxManifest.xml", "AppxManifest.xml", template=true)
    add_rule!(bundle, "windows/resources.pri", "resources.pri")
    add_rule!(bundle, "windows/MSIXAppInstallerData.xml", "Msix.AppInstaller.Data/MSIXAppInstallerData.xml")

    build(bundle, destination, parameters)
    
    if !isdir(joinpath(destination, "Assets")) # One can override assets if necessary
        img_path = get_meta_path(source, "icon.png")
        MSIXIcons.generate_app_icons(img_path, joinpath(destination, "Assets")) # override = false
    end

    return
end
