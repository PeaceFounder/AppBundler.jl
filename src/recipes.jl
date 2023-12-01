function bundle_app(platform::MacOS, source, destination; julia_version = VERSION, with_splash_screen = nothing)

    rm(destination, recursive=true, force=true)

    parameters = get_bundle_parameters("$source/Project.toml")
    app_name = parameters["APP_NAME"]

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
    
    add_rule!(bundle, "precompile.jl", "Libraries/startup/precompile.jl")
    add_rule!(bundle, "startup", "Libraries/startup")

    add_rule!(bundle, "macos/main.sh", "MacOS/$app_name", template=true, executable=true)
    add_rule!(bundle, "macos/precompile.sh", "MacOS/precompile", template=true, executable=true)
    add_rule!(bundle, "macos/Info.plist", "Info.plist", template=true)

    add_rule!(bundle, "macos/launcher.c", "Resources/launcher.c")
    add_rule!(bundle, "macos/Entitlements.plist", "Resources/Entitlements.plist")
    add_rule!(bundle, "macos/dmg_settings.py", "Resources/dmg_settings.py")

    build(bundle, app_dir, parameters)

    copy_app(source, "$app_dir/Libraries/$app_name")
    retrieve_julia(platform, "$app_dir/Libraries/julia"; version = julia_version)
    retrieve_packages(source, "$app_dir/Libraries/packages"; with_splash_screen)
    retrieve_artifacts(platform, "$app_dir/Libraries/packages", "$app_dir/Libraries/artifacts")

    return
end


function bundle_app(platform::Linux, source, destination; julia_version = VERSION, compress::Bool = isext(destination, ".snap"))

    rm(destination, recursive=true, force=true)

    # This may not be DRY enough
    parameters = get_bundle_parameters("$source/Project.toml")
    app_name = parameters["APP_NAME"]
    parameters["ARCH_TRIPLET"] = linux_arch_triplet(arch(platform))

    if compress
        app_dir = joinpath(tempdir(), basename(destination)[1:end-4])
        rm(app_dir, recursive=true, force=true)
    else
        app_dir = destination 
    end
    mkpath(app_dir)

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
    
    copy_app(source, "$app_dir/lib/$app_name")
    retrieve_julia(platform, "$app_dir/lib/julia"; version = julia_version)
    retrieve_packages(source, "$app_dir/lib/packages")
    retrieve_artifacts(platform, "$app_dir/lib/packages", "$app_dir/lib/artifacts")

    if compress
        @info "Squashing into a snap archive"
        squash_snap(app_dir, destination)
        rm(app_dir, recursive=true, force=true)
    end

    return
end


function bundle_app(platform::Windows, source, destination; julia_version = VERSION, with_splash_screen=nothing, compress::Bool = isext(destination, ".zip"))

    rm(destination, recursive=true, force=true)

    parameters = get_bundle_parameters("$source/Project.toml")
    app_name = parameters["APP_NAME"]

    if isnothing(with_splash_screen) 
        with_splash_screen = parse(Bool, parameters["WITH_SPLASH_SCREEN"])
    else
        parameters["WITH_SPLASH_SCREEN"] = with_splash_screen
    end

    if compress
        app_dir = joinpath(tempdir(), basename(destination)[1:end-4])
        rm(app_dir, recursive=true, force=true)
    else
        app_dir = destination
    end
    mkpath(app_dir)

    bundle = Bundle(joinpath(dirname(@__DIR__), "recipes"), joinpath(source, "meta"))

    add_rule!(bundle, "precompile.jl", "startup/precompile.jl")
    add_rule!(bundle, "startup", "startup") 
    add_rule!(bundle, "windows/assets", "assets") # This shall overwrite destination if it is present
    add_rule!(bundle, "icon.png", "assets/icon.png")
    add_rule!(bundle, "windows/main.ps1", "$app_name.ps1", template=true)
    add_rule!(bundle, "windows/precompile.ps1", "precompile.ps1", template=true)
    add_rule!(bundle, "windows/AppxManifest.xml", "AppxManifest.xml", template=true)
    add_rule!(bundle, "windows/main.jl", "main.jl", template=true)
    
    build(bundle, app_dir, parameters)
    
    retrieve_julia(platform, "$app_dir/julia"; version = julia_version)
    mv("$app_dir/julia/libexec/julia/lld.exe", "$app_dir/julia/bin/lld.exe") # lld.exe can't find shared libraries in UWP
    
    retrieve_packages(source, "$app_dir/packages"; with_splash_screen)
    retrieve_artifacts(platform, "$app_dir/packages", "$app_dir/artifacts")

    copy_app(source, joinpath(app_dir, app_name))
    
    if compress
        @info "Compressing into a zip archive"
        zip_directory(app_dir, destination)
        rm(app_dir, recursive=true, force=true)
    end
    
    return
end
