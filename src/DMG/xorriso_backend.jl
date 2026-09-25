# Xorrisso backend

using libdmg_hfsplus_jll: dmg
using Xorriso_jll: xorriso

struct XorrisoBackend <: ImageBackend
    hfsplus::Bool
end

function build_image(backend::XorrisoBackend, stage, img; volume_name = "", verbose = true)
    #iso_stage = tempname() 

    hfsplus_flag = backend.hfsplus ? `-hfsplus` : ``
    run(`$(xorriso()) -as mkisofs -V "$volume_name" $hfsplus_flag -relaxed-filenames -D -R -no-pad -o $img $stage`)

    #return iso_stage
end

function compress_image(backend::XorrisoBackend, img, destination; compression = :lzma)
    run(`$(dmg()) dmg $img $destination --compression=$compression`)
    return
end
