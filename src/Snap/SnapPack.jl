module SnapPack

import squashfs_tools_jll: mksquashfs, unsquashfs

using IconTools

struct IconSource
    path::String
end


struct SnapLayout
    app_exe::String
    icon::Union{IconSource, String}
    snap_config::String
    desktop_launcher::String
    configure_hook::Union{String, Nothing}
end


function materialize(source::String, destination)
    mkpath(dirname(destination))
    cp(source, destination)
    return
end

function materialize(source::IconSource, destination)
    mkpath(dirname(destination))

    img = IconTools.load(source.path)
    icon_img = IconTools.toicon(img, 512)
    IconTools.save(destination, img)

    return
end


function stage(snap::SnapLayout, destination::String)

    materialize(snap.icon, joinpath(destination, "meta/icon.png"))
    
    write(joinpath(destination, "meta/snap.yaml"), snap.snap_config)
    
    desktop_path = joinpath(destination, "meta/gui/$(snap.app_exe).desktop")
    mkpath(dirname(desktop_path))
    write(desktop_path, snap.desktop_launcher)
           
    if !isnothing(snap.configure_hook)
        configure_path = joinpath(destination, "meta/hooks/configure")
        mkpath(dirname(configure_path))
        write(configure_path, snap.configure_hook)
        chmod(configure_path, 0o755)
    end

    return
end


function pack(source, destination)

    # "." should be world-readable and executable
    chmod(source, 0o755)

    run(`$(mksquashfs()) $source $destination
        -noappend
        -comp xz
        -b 128K
        -all-root
        -no-xattrs
        -mkfs-time 0
        -all-time 0`)

    #run(`$(mksquashfs()) $source $destination -noappend -comp xz`)

    return
end

function unpack(source, destination)

    run(`$(unsquashfs()) -f -d $destination $source`)
        
    return
end

end
