# Xorrisso backend

struct XorrisoBackend
    hfsplus::Bool
end

function build_image(backend::XorrisoBackend, stage, img; volume_name = "")
    #iso_stage = tempname() 

    hfsplus_flag = backend.hfsplus ? `-hfsplus` : ``
    run(`$(xorriso()) -as mkisofs -V "$volume_name" $hfsplus_flag -relaxed-filenames -D -R -no-pad -o $img $stage`)

    #return iso_stage
end

function compress_image(backend::XorrisoBackend, img, destination; compression = :lzma)
    run(`$(dmg()) dmg $img $destination --compression=$compression`)
    return
end
