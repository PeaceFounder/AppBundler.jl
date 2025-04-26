module DMGPack

using libdmg_hfsplus_jll: dmg
using Xorriso_jll: xorriso
using rcodesign_jll: rcodesign
using ..DSStore

function generate_self_signing_pfx(pfx_path; password = "PASSWORD")

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="AppBundler" --p12-file="$pfx_path" --p12-password="$password"`)

end

# Could benefit being in it's own module DMGPack
function pack2dmg(app_stage, destination, entitlements; pfx_path = nothing, dsstore::Union{String, Dict} = nothing, password = "", compression = :lzma, installer_title = "Installer")

    isfile(entitlements) || error("Entitlements at $entitlements not found")
    isnothing(compression) || compression in [:lzma, :bzip2, :zlib, :lzfse] || error("Compression can only be `compression=[:lzma|:bzip|:zlib|:lzfse]`")
    isnothing(pfx_path) || isfile(pfx_path) || error("Signing certificate at $pfx_path not found")

    @info "Codesigning application bundle at $app_stage"
    
    if isnothing(pfx_path) 
        @warn "Creating a one time self signing certificate..."
        pfx_path = joinpath(tempdir(), "certificate_macos.pfx")
        generate_self_signing_pfx(pfx_path; password = "")
    end

    run(`$(rcodesign()) sign --shallow --p12-file "$pfx_path" --p12-password "$password" --entitlements-xml-path "$entitlements" "$app_stage"`)
    
    if !isnothing(compression)

        @info "Setting up packing stage at $(dirname(app_stage))"

        appname = splitext(basename(app_stage))[1]
        iso_stage = joinpath(tempdir(), "$appname.iso") 
        rm(iso_stage; force=true)

        rm(joinpath(dirname(app_stage), "Applications"); force=true)
        symlink("/Applications", joinpath(dirname(app_stage), "Applications"); dir_target=true)
        
        dsstore_destination = joinpath(dirname(app_stage), ".DS_Store")
        rm(dsstore_destination, force=true)

        if dsstore isa String
            
            cp(dsstore, dsstore_destination)

        elseif dsstore isa Dict

            DSStore.open_dsstore(dsstore_destination, "w+") do ds

                ds[".", "icvl"] = ("type", "icnv")
                ds[".", "vSrn"] = ("long", 1)

                for file_key in keys(dsstore)
                    file_dict = dsstore[file_key]
                    for entry_key in keys(file_dict)
                        ds[file_key, entry_key] = file_dict[entry_key]
                    end
                end
            end
        end

        @info "Forming iso archive with xorriso at $iso_stage"
        run(`$(xorriso()) -as mkisofs -V "$installer_title" -hfsplus -hfsplus-file-creator-type APPL APPL $(basename(app_stage)) -hfs-bless-by x / -relaxed-filenames -no-pad -o $iso_stage $(dirname(app_stage))`)

        @info "Compressing iso to dmg with $compression algorithm at $destination"
        run(`$(dmg()) dmg $iso_stage $destination --compression=$compression`)


        @info "Codesigning DMG bundle"
        run(`$(rcodesign()) sign --p12-file "$pfx_path" --p12-password "$password" "$destination"`)
    end

    return
end


export pack2dmg


end
