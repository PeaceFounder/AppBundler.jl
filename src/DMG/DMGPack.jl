module DMGPack

using libdmg_hfsplus_jll: dmg, hfsplus

const hfsplus_cmd = hfsplus

using hfsprogs_jll: newfs_hfs

using Xorriso_jll: xorriso
using rcodesign_jll: rcodesign
using ..DSStore
using ..HFS



function generate_self_signing_pfx(pfx_path; password = "PASSWORD")

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="AppBundler" --p12-file="$pfx_path" --p12-password="$password"`)

end



"""
    remove_symlinks(target; inline=false, warn=true)

Recursively removes all symlinks from `target`.

If `inline=false`, all symlinks are removed.

If `inline=true`, symlinks to files are replaced with copies of their
targets. Inlining symlinks to directories is not supported and throws
an `ArgumentError`.

If `warn=true`, a warning is emitted for every symlink encountered.
"""
function remove_symlinks(target; inline=false, warn=true)
    for (root, dirs, files) in walkdir(target; follow_symlinks=false)
        # Directory symlinks
        for name in dirs
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)

                if !isabspath(link_target)
                    link_target = joinpath(root, link_target)
                end

                link_target = normpath(link_target)

                if inline
                    throw(ArgumentError(
                        "Inlining symlinked directories is not supported: " *
                        "$path -> $link_target"
                    ))
                end

                warn && @warn "Removing symlink" path target=link_target
                rm(path)
            end
        end

        # File symlinks
        for name in files
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)

                if !isabspath(link_target)
                    link_target = joinpath(root, link_target)
                end

                link_target = normpath(link_target)

                warn && @warn "Removing symlink" path target=link_target

                if inline
                    rm(path)
                    cp(link_target, path)
                else
                    rm(path)
                end
            end
        end
    end

    return nothing
end


"""
    extract_symlinks(target; warn=true)

Find all symlinks recursively below `target`, remove them, and return their
locations and original link targets.

The symlink path is relative to `target`. The target is preserved exactly
as returned by `readlink`, so relative symlink targets remain relative.
"""
function extract_symlinks(target; warn=true)
    target = abspath(target)
    symlinks = Tuple{String, String}[]

    for (root, dirs, files) in walkdir(target; follow_symlinks=false)
        for name in Iterators.flatten((dirs, files))
            path = joinpath(root, name)

            if islink(path)
                link_target = readlink(path)
                relative_path = relpath(path, target)

                warn && @warn "Extracting symlink" path=relative_path target=link_target

                push!(symlinks, (relative_path, link_target))
                rm(path)
            end
        end
    end

    return symlinks
end


"""
    add_symlinks(image, symlinks)

Add symlinks to an HFS+ image.

`symlinks` is expected to be a collection of `(path, target)` tuples,
where `path` is relative to the staging root and `target` is the original
symlink target as returned by `readlink`.
"""
# function add_symlinks(image, symlinks)
#     for (path, target) in symlinks
#         # hfsplus expects the link path and target as filesystem paths.
#         # Keep the original target unchanged so relative links remain
#         # relative to the symlink's directory.
#         run(`$(hfsplus) $image symlink $target $path`)
#     end

#     return nothing
# end

function add_symlinks(image, symlinks)
    for (path, link_target) in symlinks
        run(`$(hfsplus()) $image symlink $path $link_target`)
    end

    return nothing
end



"""
    pack(app_stage, destination, entitlements; pfx_path = nothing, password = "", compression = :lzma, installer_title = "Installer")

Create a macOS disk image (DMG) from an application bundle with code signing and customizable appearance.

This function handles the complete process of packaging a macOS application for distribution. It code signs the application bundle with appropriate entitlements, creates a professional-looking installer disk image with optional custom appearance, sets up the drag-and-drop installation experience by including a symbolic link to Applications, applies the selected compression algorithm to minimize file size, and code signs the final DMG for security and integrity. The resulting DMG file follows Apple's distribution guidelines and provides end users with the familiar installation experience of dragging the application to their Applications folder.

The function assumes that `app_stage` points to a properly structured macOS application bundle (`.app` directory). Importantly, the parent directory of `app_stage` serves as the staging area from which the DMG file is created. This means that any files present in this parent directory will be included in the final DMG. The function automatically creates a symbolic link to `/Applications` in this parent directory to facilitate drag-and-drop installation, and it may modify or create a `.DS_Store` file in this directory to control the appearance of the DMG when opened.

# Arguments
- `app_stage::String`: Path to the application bundle (`.app` directory) to be packaged
- `destination::String`: Path where the resulting DMG file should be saved
- `entitlements::String`: Path to an XML file containing the entitlements for code signing

# Keyword Arguments
- `pfx_path::Union{String, Nothing} = nothing`: Path to a PKCS#12 certificate file for code signing. If not provided, a temporary self-signed certificate will be generated
- `password::String = ""`: Password for the certificate file
- `compression::Union{Symbol, Nothing} = :lzma`: Compression algorithm to use for the DMG. Options are `:lzma`, `:bzip2`, `:zlib`, `:lzfse`, or `nothing` for no compression
- `installer_title::String = "Installer"`: Volume name for the DMG
"""
function pack(app_stage, destination, entitlements; pfx_path = nothing, password = "", compression = :lzma, installer_title = "Installer", hardened_runtime = true, shallow_signing = true, hfsplus = true)
    
    hfsplus = true
    
    isfile(entitlements) || error("Entitlements at $entitlements not found")
    isnothing(compression) || compression in [:lzma, :bzip2, :zlib, :lzfse] || error("Compression can only be `compression=[:lzma|:bzip|:zlib|:lzfse]`")
    isnothing(pfx_path) || isfile(pfx_path) || error("Signing certificate at $pfx_path not found")

    # if isnothing(pfx_path) 
    #     @warn "Creating a one time self signing certificate..."
    #     pfx_path = joinpath(tempdir(), "certificate_macos.pfx")
    #     generate_self_signing_pfx(pfx_path; password = "")
    # end

    shallow_flag = shallow_signing ? `--shallow` : ``
    runtime_flag = hardened_runtime ? `--code-signature-flags runtime` : ``

    #remove_symlinks(app_stage) # will it actually work?

    if !isnothing(pfx_path)
        println("Codesigning application bundle at $app_stage with certificate at $pfx_path")
        run(`$(rcodesign()) sign $shallow_flag --p12-file "$pfx_path" --p12-password "$password" $runtime_flag --entitlements-xml-path "$entitlements" "$app_stage"`)
    else
        @warn "Skipping codesigning. Use `--selfsign` to codesign your code with self signed certificate."
    end

    if !isnothing(compression)

        img_stage = tempname() 

        if hfsplus

            #hfsplus = libdmg_hfsplus_jll.hfsplus # dirty fix

            stage = dirname(app_stage)

            #println("Forming hfs archive with xorriso at $img_stage")

            # Need to replace Applications link in the parrent stage
            # This is a dirty fix for now. We need to think whether this needs to be refactored
            #rm(joinpath(dirname(app_stage), "Applications"); force = true)
            #rm(joinpath(stage, "Applications"); force = true)


            symlinks = extract_symlinks(dirname(app_stage))

            println("Forming hfs archive with hfsplus at $img_stage")



            # `du -s` reports 512-byte blocks on macOS.
            du_blocks = parse(Int, split(strip(read(`du -s $stage`, String)))[1])

            # ~2% slack, following the original shell recipe.
            size = du_blocks ÷ 1000 * 102 ÷ 100 + 1

            # Create and format the HFS+ filesystem.
            run(`dd if=/dev/zero of=$img_stage bs=1M count=$size`)
            run(`$(newfs_hfs()) -v $installer_title $img_stage`)

            # Create the drag-to-Applications symlink.
            #run(`$(hfsplus_cmd()) $img_stage symlink "/ " /Applications`)

            # Populate the filesystem.
            run(`$(hfsplus_cmd()) $img_stage addall $stage`)

            
            # So how can we add symlinks
            add_symlinks(img_stage, symlinks)
            
        else

            println("Forming iso archive with xorriso at $img_stage")
            run(`$(xorriso()) -as mkisofs -V "$installer_title" -relaxed-filenames -D -R -no-pad -o $img_stage $(dirname(app_stage))`)

        end

        println("Compressing img to dmg with $compression algorithm at $destination")
        run(`$(dmg()) dmg $img_stage $destination --compression=$compression`)
            

        if !isnothing(pfx_path)
            println("Codesigning DMG bundle with certificate at $pfx_path")
            run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
        end
    end

    return
end

function unpack(source, destination)

    raw_image = tempname()
    run(`$(dmg()) extract $source $raw_image`)
    HFS.extract_hfs_filesystem(raw_image, destination)
    HFS.explore_hfs_image(raw_image)

    return
end

"""
    replace_file_with_hash(filepath::String)

Computes the code hash of a file using rcodesign and replaces the file 
with the rcodesign output directly.
"""
function replace_binary_with_hash(filepath::String)
    if !isfile(filepath)
        error("File does not exist: $filepath")
    end
    
    try
        # Get rcodesign output and write directly to file
        hash_output = read(`$(rcodesign()) compute-code-hashes $filepath`, String)
        lines = split(strip(hash_output), '\n')
        stripped_output = join(lines[2:end], '\n') * '\n'
        write(filepath, stripped_output)
        println("Replaced $filepath with its hash(es)")
        return hash_output
    catch e
        error("Failed to process $filepath: $e")
    end
end

end
