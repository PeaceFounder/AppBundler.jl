using AppBundler: julia_download_url
import Pkg.BinaryPlatforms: Linux, Windows, MacOS

using Test

@test julia_download_url(Windows(:x86_64), v"1.9.3") == "https://julialang-s3.julialang.org/bin/winnt/x64/1.9/julia-1.9.3-win64.zip"

@test julia_download_url(Linux(:x86_64, libc=:glibc), v"1.9.3") == "https://julialang-s3.julialang.org/bin/linux/x64/1.9/julia-1.9.3-linux-x86_64.tar.gz"
@test julia_download_url(Linux(:aarch64), v"1.9.3") == "https://julialang-s3.julialang.org/bin/linux/aarch64/1.9/julia-1.9.3-linux-aarch64.tar.gz"

@test julia_download_url(MacOS(:x86_64), v"1.9.3") == "https://julialang-s3.julialang.org/bin/mac/x64/1.9/julia-1.9.3-mac64.tar.gz"
@test julia_download_url(MacOS(:aarch64), v"1.9.3") == "https://julialang-s3.julialang.org/bin/mac/aarch64/1.9/julia-1.9.3-macaarch64.tar.gz"

#https://julialang-s3.julialang.org/bin/mac/aarch64/1.9/julia-1.9.3-macaarch64.tar.gz
#https://julialang-s3.julialang.org/bin//mac/aarch64/1.9/julia-1.9.2-macaarch64.tar.gz
