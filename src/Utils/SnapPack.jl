module SnapPack

import squashfs_tools_jll

function pack2snap(source, destination)
    
    if squashfs_tools_jll.is_available()    
        mksquashfs = squashfs_tools_jll.mksquashfs()
    else
        @info "squashfs-tools not available from jll. Attempting to use mksquashfs from the system."
        mksquashfs = "mksquashfs"
    end

    run(`$mksquashfs $source $destination -noappend -comp xz`)

    return
end

end
