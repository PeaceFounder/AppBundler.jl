using libdmg_hfsplus_jll: dmg
using xorriso_jll: xorriso
using rcodesign_jll: rcodesign
using Clang_jll: clang
using AppBundlerUtils_jll

function generate_self_signing_pfx(source, destination; password = "PASSWORD")

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="AppBundler" --p12-file="$destination" --p12-password="$password"`)

end


function get_macos_launcher_path(arch)

    return AppBundlerUtils_jll.macos_launcher_path
end


# debug means that intermidiary stages are placed at the destination directory and if previous stage is found it is continued from there
# the signing key could be passed as an evironment variable
# MACOS_PFX = ...
# MACOS_PFX_PASSWORD = ...
# if unset a self signing certificate could be used instead
# placing it at the meta folder as macos.pfx seems like a good option
function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), compression =:lzma, debug = true, precompile = true)

    # warn that precompilation can not happen on the host system as desitnation is different
    appname = splitext(basename(destination))[1]
    
    staging_dir = debug ? dirname(destination) : joinpath(tempdir(), appname) 
    app_stage = compress ? joinpath(staging_dir, "$appname/$appname.app") : destination
    iso_stage = joinpath(staging_dir, "$appname.iso") 

    if !debug
        rm(app_stage; force=true, recursive=true)
        rm(iso_stage; force=true)
        rm(destination; force=true)
    end

    if !isdir(app_stage)
        bundle_app(platform, source, app_stage)
        precompile_script = "$app_stage/Contents/MacOS/precompile"
        run(`$precompile_script`)

        run(`find $app_stage -name "._*" -delete`)
        rm("$app_stage/Contents/MacOS/precompile")
    end

    password = get(ENV, "MACOS_PFX_PASSWORD", "")
    pfx_path = joinpath(source, "meta", "macos", "certificate.pfx")
    if !isfile(pfx_path) 
        @warn "meta/macos.pfx not found. Creating a one time self signing certificate..."
        # generate a self signing certificate here
        pfx_path = joinpath(tempdir(), "certificate_macos.pfx")
        generate_self_signing_pfx(source, pfx_path; password = "")
    end

    # I need to compile the file 

    if !isfile("$app_stage/Contents/MacOS/main")
        mv("$app_stage/Contents/MacOS/gtkapp", "$app_stage/Contents/MacOS/main")
    end

    arch = "arm64"
    launcher_path = get_macos_launcher_path(arch)
    cp(launcher_path, "$app_stage/Contents/MacOS/gtkapp"; force=true)
    chmod("$app_stage/Contents/MacOS/gtkapp", 0o755)


    run(`$(rcodesign()) sign --shallow --p12-file "$pfx_path" --p12-password "$password" --entitlements-xml-path "$app_stage/Contents/Resources/Entitlements.plist" "$app_stage"`)

    if !compress
        return
    else

        rm(joinpath(dirname(app_stage), "Applications"); force=true)
        symlink("/Applications", joinpath(dirname(app_stage), "Applications"); dir_target=true)

        run(`$(xorriso()) -as mkisofs -V "MyApp" -hfsplus -hfsplus-file-creator-type APPL APPL $(basename(app_stage)) -hfs-bless-by x / -relaxed-filenames -no-pad -o $iso_stage $(dirname(app_stage))`)

        run(`$(dmg()) dmg $iso_stage $destination --compression=lzma`)

        run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
    end

    return
end


