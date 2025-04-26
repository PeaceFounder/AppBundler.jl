function build_app(platform::MacOS, source, destination; compression = isext(destination, ".dmg") ? :lzma : nothing, debug = false, precompile = true, incremental = true)

    if precompile && (!Sys.isapple() || (Sys.ARCH == "x86_64" && arch(platform) != Sys.ARCH))
        error("Precompilation can only be done on MacOS as currently Julia does not support cross compilation. Set `precompile=false` to make a bundle without precompilation.")
    end

    parameters = get_bundle_parameters("$source/Project.toml")
    appname = parameters["APP_NAME"]
    
    staging_dir = debug ? dirname(destination) : joinpath(tempdir(), appname) 
    app_stage = !isnothing(compression) ? joinpath(staging_dir, "$appname/$appname.app") : destination

    if !debug
        rm(app_stage; force=true, recursive=true)
        rm(destination; force=true)
    end

    if !isdir(app_stage)
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
            run(`$julia --eval '_precompile()'`)
            # end
            
        else
            @info "Precompilation disabled. Precompilation will happen on the desitination system at first launch."
        end

        # May not be the only ones
        run(`find $app_stage -name "._*" -delete`)
    end

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

# ToDo: MSIX building functionality
build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".zip"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, debug::Bool = false) = bundle_app(platform, source, destination; compress, path_length_threshold, skip_long_paths, debug)
