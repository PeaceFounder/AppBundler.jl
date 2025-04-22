using libdmg_hfsplus_jll: dmg
using Xorriso_jll: xorriso
using rcodesign_jll: rcodesign

function generate_self_signing_pfx(source, destination; password = "PASSWORD")

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="AppBundler" --p12-file="$destination" --p12-password="$password"`)

end

function build_app(platform::MacOS, source, destination; compress::Bool = isext(destination, ".dmg"), compression =:lzma, debug = true, precompile = true, incremental = true)

    if precompile && (!Sys.isapple() || (Sys.ARCH == "x86_64" && arch(platform) != Sys.ARCH))
        error("Precompilation can only be done on MacOS as currently Julia does not support cross compilation. Set `precompile=false` to make a bundle without precompilation.")
    end

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

        if precompile
            @info "Precompiling"

            if !incremental
                rm("$app_stage/Contents/Libraries/julia/share/julia/compiled", recursive=true)
            end

            julia = "$app_stage/Contents/Libraries/julia/bin/julia"
            startup = "$app_stage/Contents/Libraries/julia/etc/julia/startup.jl"
            
            # Run the command with the modified environment
            # withenv("JULIA_DEBUG" => "loading") do
            run(`$julia --eval '_precompile()'`)
            # end
            
        else
            @info "Precompilation disabled. Precompilation will happen on the desitination system at first launch."
        end

        # I could write tests and check them with thoose ones
        run(`find $app_stage -name "._*" -delete`)
        #rm("$app_stage/Contents/MacOS/precompile")
    end

    password = get(ENV, "MACOS_PFX_PASSWORD", "")
    pfx_path = joinpath(source, "meta", "macos", "certificate.pfx")
    if !isfile(pfx_path) 
        @warn "meta/macos.pfx not found. Creating a one time self signing certificate..."
        # generate a self signing certificate here
        pfx_path = joinpath(tempdir(), "certificate_macos.pfx")
        generate_self_signing_pfx(source, pfx_path; password = "")
    end

    entitlements_path = joinpath(source, "meta/macos/Entitlements.plist")
    if isfile(entitlements_path)
        @info "Using entitlements $entitlements_path"
    else
        @info "No override found at $entitlements_path; using default override"
        entitlements_path = joinpath(dirname(@__DIR__), "recipes/macos/Entitlements.plist")
    end

    run(`$(rcodesign()) sign --shallow --p12-file "$pfx_path" --p12-password "$password" --entitlements-xml-path "$entitlements_path" "$app_stage"`)

    if compress
        rm(joinpath(dirname(app_stage), "Applications"); force=true)
        symlink("/Applications", joinpath(dirname(app_stage), "Applications"); dir_target=true)

        run(`$(xorriso()) -as mkisofs -V "MyApp" -hfsplus -hfsplus-file-creator-type APPL APPL $(basename(app_stage)) -hfs-bless-by x / -relaxed-filenames -no-pad -o $iso_stage $(dirname(app_stage))`)

        run(`$(dmg()) dmg $iso_stage $destination --compression=lzma`)

        run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
    end

    return
end
