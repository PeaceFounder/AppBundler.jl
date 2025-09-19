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


function get_path(prefix::Vector, suffix::Vector; dir = false, warn = true)

    for i in prefix
        for j in suffix
            fname = joinpath(i, j)
            if isfile(fname) || (dir && isdir(fname))
                return fname
            end
        end
    end
    
    if warn
        @warn "No option for $suffix found"
    end

    return
end

get_path(prefix::String, suffix::String) = get_path([prefix], [suffix])
get_path(prefix::String, suffix::Vector) = get_path([prefix], suffix)
get_path(prefix::Vector, suffix::String) = get_path(prefix, [suffix])

function MSIX(;
              prefix = joinpath(dirname(@__DIR__), "recipes"),
              icon = get_path(prefix, ["windows/Assets", "windows/icon.png", "icon.png"]; dir = true),
              appxmanifest = get_path(prefix, "windows/AppxManifest.xml"),
              resources_pri = get_path(prefix, "windows/resources.pri"),
              msixinstallerdata = get_path(prefix, "windows/MSIXAppInstallerData.xml"),
              path_length_threshold = 260,
              skip_long_paths = false,
              pfx_cert = get_path(prefix, "windows/certificate.pfx"), # We actually want the warning
              parameters = Dict()
              )
    
    return MSIX(icon, appxmanifest, msixinstallerdata, resources_pri, path_length_threshold, skip_long_paths, pfx_cert, parameters)
end


function MSIX(overlay; **kwargs)
    
    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]

    # ToDo: refactor setting of the defaults
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return MSIX(; prefix, parameters, **kwargs)
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
              icon = get_path(prefix, ["linux/icon.png", "icon.png"]),
              snap_config = get_path(prefix, "linux/snap.yaml"),
              desktop_launcher = get_path(prefix, "linux/main.desktop"),
              configure_hook = get_path(prefix, "linux/configure.sh"),
              parameters = Dict()
              )

    return Snap(icon, snap_config, desktop_launcher, configure_hook, parameters)
end

function Snap(overlay; **kwargs)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return Snap(; prefix, parameters, **kwargs)
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
             icon = get_path(prefix, ["macos/icon.icns", "macos/icon.png", "icon.icns"]),
             info_config = get_path(prefix, "macos/Info.plist"),
             entitlements = get_path(prefix, "macos/Entitlements.plist"),
             dsstore = get_path(prefix, ["macos/DS_Store.toml", "macos/DS_Store"]),
             pfx_cert = get_path(prefix, "macos/certificate.pfx"),
             parameters = Dict()
             )

    return DMG(icon, info_config, entitlements, dsstore, pfx_cert, parameters)
end

function DMG(overlay; **kwargs)

    prefix = [overlay, joinpath(overlay, "meta"), joinpath(dirname(@__DIR__), "recipes")]
    
    parameters = get_bundle_parameters(joinpath(overlay, "Project.toml"))

    return DMG(; prefix, parameters, **kwargs)
end


function install(source, destination; parameters = Dict(), force = false, executable = false)

    if isfile(destination) 
        if force
            rm(destination)
        else
            error("$destination already exists. Use force = true to overwrite")
        end
    else
        mkpath(dirname(destination))
    end

    template = Mustache.load(source)

    open(destination, "w") do file
        Mustache.render(file, template, parameters)
    end

    if executable
        chmod(destination, 0o755)
    end

    return
end

function stage(msix::MSIX, destination::String)

    if !isdir(destination)
        mkdir(destination)
    end

    if isdir(msix.icon)
        @info "Treating icon path as assets directory"
        install(msix.icon, joinpath(destination, "Assets"))
    else
        MSIXIcons.generate_app_icons(msix.icon, joinpath(destination, "Assets")) 
    end

    (; parameters) = msix
    install(msix.appxmanifest, joinpath(destination, "AppxManifest.xml"); parameters)
    cp(msix.resources_pri, joinpath(destination, "resources.pri"))
    install(msix.msixinstallerdata, joinpath(destination, "Msix.AppInstaller.Data/MSIXAppInstallerData.xml"); parameters))

    return
end

function bundle(setup::Function, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), pfx_password = get(ENV, "WINDOWS_PFX_PASSWORD", ""))

    rm(destination; force=true, recursive=true)

    app_stage = compress ? mktempdir() : destination

    if !isdir(app_stage)
        mkdir(app_stage)
    end
    
    # bundle_msix(source, app_stage; parameters)

    stage(msix, app_stage)

    (; path_length_threshold, skip_long_paths) = msix

    setup(app_stage)

    if compress

        MSIXPack.pack2msix(app_stage, destination; pfx_path = msix.pfx_cert, password, path_length_threshold, skip_long_paths)        
        
    end    
end

function install_dsstore(source::String, dsstore_destination::String)

    if last(splitext(dmg.dsstore)) == ".toml"
        dsstore = TOML.parse(dmg.dsstore)

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
        cp(dmg.dsstore, dsstore_destination)
    end

    return
end

# main redirect is an option one can opt in during the staging
function stage(dmg::DMG, destination::String; dsstore = false, main_redirect = false, arch = :x86_64) # destination folder is used as appdir

    (; parameters) = dmg
    app_name = parameters["APP_NAME"]

    cp(dmg.icon, joinpath(destination, "Resources/icon.icns"))
    install(dmg.config, joinpath(destination, "Info.plist"); parameters)

    if main_redirect
        mkdir(joinpath(destination, "Contents/MacOS"))
        retrieve_macos_launcher(MacOS(arch), joinpath(destination, "Contents/MacOS/$app_name")) 
    end

    if dsstore
        install_dsstore(dmg.dsstore, joinpath(dirname(destination), ".DS_Store"))
    end

    return
end

function stage(snap::Snap, destination::String; install_configure = false)

    (; parameters) = snap
    app_name = parameters["APP_NAME_LOWERCASE"]

    cp(snap.icon, joinpath(destination, "meta/icon.png"))
    install(snap.snap_config, joinpath(destination, "meta/snap.yaml"), parameters)
    install(snap.desktop_launcher, joinpath(destination, "meta/gui/$app_name.desktop"))
    
    if install_configure
        install(snap.configure_hook, joinpath(destination, "meta/hooks/configure"); executable = true)
    end

    return
end

function bundle(setup::Function, dmg::DMG, destination::String; compress::Bool = isext(dest, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), main_redirect = false, arch = :x86_64) 

    if ispath(destination)
        if force
            rm(destination; force=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    if compress
        app_stage = joinpath(mktempdir(), basename(destination))
        stage(dmg, app_stage; dsstore = true)        
    else
        app_stage = destination
        stage(dmg, app_stage; dsstore = false)        
    end

    stage(dmg, app_stage; dsstore, main_redirect, arch)
    setup(app_stage)
    
    installer_title = join([dmg.parameters["APP_DISPLAY_NAME"], "Installer"], " ")

    if compress
        DMGPack.pack2dmg(app_stage, destination, dmg.entitlements; pfx_path = dmg.pfx_cert, password, compression, installer_title)
    end

    return
end

function bundle(setup::Function, msix::MSIX, destination::String; compress::Bool = isext(destination, ".msix"), force = false, password = get(ENV, "WINDOWS_PFX_PASSWORD", ""))

    if ispath(destination)
        if force
            rm(destination; force=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = compress ? mktempdir() : destination

    stage(msix, app_stage)    
    setup(app_stage)

    # ToDo: move path_length_threshold and skip_long_paths checks here

    if compress
        (; path_length_threshold, skip_long_paths) = msix
        MSIXPack.pack2msix(app_stage, destination; pfx_path = msix.pfx_cert, password, path_length_threshold, skip_long_paths)        
    end
    
    return
end

function bundle(setup::Function, snap::Snap, destination::String; compress::Bool = isext(destination, ".snap"), force = false, install_configure = false)

    if ispath(destination)
        if force
            rm(destination; force=true)
        else
            error("Destination $destination already exists. Use `force = true` argument.")
        end
    end

    app_stage = compress ? mktempdir() : destination

    stage(snap, app_stage; install_configure)    
    setup(app_stage)

    if compress
        SnapPack.pack2snap(app_stage, destination)
    end

    return
end


