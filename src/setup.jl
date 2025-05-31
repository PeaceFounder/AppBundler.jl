using Random: RandomDevice
using Base64
using rcodesign_jll: rcodesign

function generate_macos_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)
    
    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))
        
    destination = joinpath(root, "meta/macos/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="$person_name" --p12-file="$destination" --p12-password="$password" --country-name=$country --validity-days="$validity_days"`)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/macos/certificate.pfx; To use certificate set certificate password with environment variable:

        export MACOS_PFX_PASSWORD="$password"
    """)

    ENV["MACOS_PFX_PASSWORD"] = password

    return
end


function generate_windows_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)

    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))

    destination = joinpath(root, "meta/windows/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))
    
    MSIXPack.generate_self_signed_certificate(destination; password, name = person_name, country, validity_days)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/windows/certificate.pfx; To use certificate set certificate password with environment variable:

        export WINDOWS_PFX_PASSWORD="$password"
    """)
    
    ENV["WINDOWS_PFX_PASSWORD"] = password

    return
end
