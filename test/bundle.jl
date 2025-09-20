using Test
import AppBundler: stage, bundle, MSIX, DMG, Snap
import AppBundler

using SHA

function hash_stage(f)
    stage = mktempdir()
    f(stage)
    return hash_directory(stage)
end

# Read file and compute SHA-256 hash
function hash_file(filename)
    hash_bytes = sha256(read(filename))
    hash_string = bytes2hex(hash_bytes)
    return hash_string
end    

function hash_directory(dir_path)
    if !isdir(dir_path)
        error("Directory not found: $dir_path")
    end
    
    # Get all files recursively and sort for consistency
    all_files = String[]
    for (root, dirs, files) in walkdir(dir_path)
        for file in files
            push!(all_files, joinpath(root, file))
        end
    end
    sort!(all_files)  # Ensure consistent ordering
    
    # Create hash context properly
    ctx = SHA.SHA256_CTX()  # Create context this way
    
    # Hash each file's content
    for filepath in all_files
        file_data = read(filepath)
        SHA.update!(ctx, file_data)
    end
    
    return bytes2hex(SHA.digest!(ctx))
end

# ------------------------ MSIX -------------------

# ToDo: add signature tests as well

msix = MSIX("examples/gtkapp")
@test hash_stage() do dest
    stage(msix, dest)
end == "4495ecd3cba091bdd0c7821cf7e481f2acff4e479ea6fd85b6dc895bb5700b66"

# The hashes does not match with stage because:
# - AppxManifest.xml publisher is updated during packing
@test hash_stage() do stage_dir

    @show stage_dir

    dest = joinpath(mktempdir(), "gtkapp.msix")
    bundle(msix, dest) do app_stage
        @info "The MSIX app stage is $app_stage"
    end

    AppBundler.MSIXPack.unpack(dest, stage_dir)
    rm(joinpath(stage_dir, "AppxSignature.p7x")) # Signatures are always nondeterministic

    # @test hash_file(joinpath(stage_dir, "AppxBlockMap.xml")) == "70ff6695ec913326f645c1cd30e48f75f57545ee4ae546db5843bf0779e6ee7e"
    rm(joinpath(stage_dir, "AppxBlockMap.xml")) # AppxBlockMap.xml has a slight nondeterminism
end == "d83e13d2d066bbc7cc5e8626c50085ba2563c3dfacbbb62b6df2945f8f78379b" 


# # ------------------- DMG -------------

dmg = DMG("examples/gtkapp")
@test hash_stage() do dest
    stage(dmg, joinpath(dest, "gtkapp.app"); dsstore=true, main_redirect=true)
end == "febd3cfc289fccc66308ac0726b800d821e025b97072a44a90119c46639162bc"


@show hash_stage() do stage_dir

    dest = joinpath(mktempdir(), "gtkapp.dmg")
    bundle(dmg, dest; main_redirect=true) do app_stage
        @info "The DMG app stage is $app_stage"
    end

    AppBundler.DMGPack.unpack(dest, stage_dir)
    rm(joinpath(stage_dir, "gtkapp.app/Contents/MacOS/gtkapp"))

end  == "53e0b0121d61f1ee3cd4485944383af73a5fd16cadee53a004cde44bfe2431c3"


# # -------------------- SNAP -----------------

# snap = Snap("examples/gtkapp")
# @test hash_stage() do dest
#     stage(snap, dest; install_configure=true)
# end == "947184f6a758540e3b2a60701c8c92790264edd6db3319bbadaa5fb55a0e8dc6"


# dest = joinpath(mktempdir(), "gtkapp.snap")
# bundle(snap, dest) do app_stage
#     @info "The Snap app stage is $app_stage"
# end
# hash_snap = hash_file(dest)




