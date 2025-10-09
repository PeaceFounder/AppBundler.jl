# ToDo: rename the file to recipes

function bundle(product::PkgImage, dmg::DMG, destination::String; compress::Bool = isext(dest, ".dmg"), compression = :lzma, force = false, password = get(ENV, "MACOS_PFX_PASSWORD", ""), arch = :x86_64)
    
    bundle(dmg, destination; compress, compression, force, password, main_redirect = true, arch) do app_stage
        # app_stage always points to app directory
        stage(product, MacOS(arch), joinpath(app_stage, "Contents/Libraries"))

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "macos/startup.jl")
        install(startup_file, joinpath(app_stage, "Contents/Libraries/etc/julia/startup.jl"); parameters = dmg.parameters, force = true)

        # main redirect
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "macos/main.sh")
        install(main_file, joinpath(app_stage, "Contents/Libraries/main"); parameters = dmg.parameters, executable = true)
        
    end

    return
end

function bundle(product::PkgImage, snap::Snap, destination::String; compress::Bool = isext(dest, ".snap"), force = false, arch = :x86_64)
    
    bundle(snap, destination; compress, force, install_configure = true) do app_stage
        
        stage(product, Linux(arch), app_stage)

        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "linux/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = snap.parameters, force = true)
        
        
        main_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "linux/main.sh")
        install(main_file, joinpath(app_stage, "main"); parameters = snap.parameters, executable = true)

    end

    return
end


function bundle(product::PkgImage, msix::MSIX, destination::String; compress::Bool = isext(dest, ".msix"), force = false, arch = :x86_64, windowed = true)

    bundle(msix, destination; compress, force) do app_stage
        
        stage(product, Windows(arch), app_stage)
        
        startup_file = get_path([joinpath(product.source, "meta"), joinpath(dirname(@__DIR__), "recipes")], "windows/startup.jl")
        install(startup_file, joinpath(app_stage, "etc/julia/startup.jl"); parameters = msix.parameters, force = true)
        
        if windowed
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/julia.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
            WinSubsystem.change_subsystem_inplace("$app_stage/bin/lld.exe"; subsystem_flag = WinSubsystem.SUBSYSTEM_WINDOWS_GUI)
        end
    end

    return
end

# kwargs could be passed to MSIX
function build_app(platform::Windows, source, destination; compress::Bool = isext(destination, ".msix"), precompile = true, incremental = true, force = false, windowed = true)

    msix = MSIX(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, msix, destination; compress, force, windowed, arch = arch(platform))
end

function build_app(platform::Linux, source, destination; compress::Bool = isext(destination, ".snap"), precompile = true, incremental = true, force = false)

    snap = Snap(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, snap, destination; compress, force, arch = arch(platform))
end

function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), precompile = true, incremental = true, force = false)

    dmg = DMG(source)
    product = PkgImage(source; precompile, incremental)
    
    return bundle(product, dmg, destination; compress, force, arch = arch(platform))
end

