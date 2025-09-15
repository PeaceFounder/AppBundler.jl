struct MSIX
    icon::String
    config::String
    installer_config::String
    resources_pri::String
    pfx_cert::Union{String, Nothing}
    path_length_threshold::Int = 260
    skip_long_paths::Bool = false
end

struct Snap
    icon::String
    config::String
    launcher::String
end

struct DMG
    icon::String
    config::String
    entitlements::String
    main_redirect::Bool
    pfx_cert::Union{String, Nothing}
    #notary::Nothing
end


function bundle(setup::Function, msix::MSIX, dest::String, compress::Bool = true, pfx_password = "")

    # collect all the configuraion files and then run
    setup(staging_dir)
    # finally check
    check_long_path_threshold(staging_dir)
    
    compress_bundle(staging_dir, dest)

    sign_msix_bundle(dest, pfx_path)
end


abstract type Product end

struct PkgImage <: Product
    source::String
    precompile::Bool
    incremental::Bool
end

struct SysImage <: Product end

struct Trim <: Product end


function bundle(product::Product, msix::MSIX, dest::String, compress::Bool = true, pfx_password = "", debug::Bool = false)

    bunlde(msix, dest; compress, pfx_password) do stagging_dir
        
        stage(product, stagging_dir)

        # collect source and compile it here 
    end

end

# build(PkgImage(source), MSIX(source), dest; platform = :x86_64)

# stage(product, stagging_dir)

# bundle/stage seems more appropriate


function build(product::Product, dest::String)

end
