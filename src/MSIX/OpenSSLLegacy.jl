module OpenSSLLegacy

using Artifacts

openssl() = joinpath(artifact"OpenSSL", "bin/openssl")

export openssl

end
