"""
    build_app(platform::MacOS, source, destination; compression = :lzma, debug = false, precompile = true, incremental = true)

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
- `debug::Bool = false`: When true, creates the staging directory in the same location as the destination
  instead of in a temporary directory, and preserves existing files for debugging purposes
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
#build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".zip"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, debug::Bool = false) = bundle_app(platform, source, destination; compress, path_length_threshold, skip_long_paths, debug)

function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), path_length_threshold::Int = 260, skip_long_paths::Bool = false, debug::Bool = false, precompile = false, incremental = true) 

    if compress
        app_stage = joinpath(tempdir(), "msixapp")
    else
        app_stage = destination
    end


    if !debug
        rm(app_stage; force=true, recursive=true)
        rm(destination; force=true)
    end

    
    if !isdir(app_stage)

        bundle_app(platform, source, app_stage)

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

    end


    if compress
        
        password = get(ENV, "WINDOWS_PFX_PASSWORD", "")

        pfx_path = joinpath(source, "meta", "windows", "certificate.pfx")
        if !isfile(pfx_path)
            pfx_path = nothing
        end

        MSIXPack.pack2msix(app_stage, destination; pfx_path, password, path_length_threshold, skip_long_paths)        
        
    end

end
