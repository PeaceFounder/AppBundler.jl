import TOML

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
              icon = get_path(prefix, ["linux/icon.png", "icon.png"]),
              snap_config = get_path(prefix, "linux/snap.yaml"),
              desktop_launcher = get_path(prefix, "linux/main.desktop"),
              configure_hook = get_path(prefix, "linux/configure.sh"),
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
             icon = get_path(prefix, ["macos/icon.icns", "macos/icon.png", "icon.icns"]),
             info_config = get_path(prefix, "macos/Info.plist"),
             entitlements = get_path(prefix, "macos/Entitlements.plist"),
             dsstore = get_path(prefix, ["macos/DS_Store.toml", "macos/DS_Store"]),
             pfx_cert = get_path(prefix, "macos/certificate.pfx"),
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
