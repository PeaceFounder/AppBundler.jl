module SnapPack

import squashfs_tools_jll: mksquashfs, unsquashfs

function pack(source, destination)

    run(`$(mksquashfs()) $source $destination -noappend -comp xz`)

    return
end

function unpack(source, destination)

    run(`$(unsquashfs()) -f -d $destination $source`)
        
    return
end

end
