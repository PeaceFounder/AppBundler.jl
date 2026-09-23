module SnapPack

import squashfs_tools_jll: mksquashfs, unsquashfs

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
