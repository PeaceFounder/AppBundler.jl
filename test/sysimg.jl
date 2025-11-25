# using AppBundler.SysImgTools: compile_sysimage #, SysImgBase


# # create_fresh_base_sysimage, create_sysimage, create_sysimage_pkgcompiler


# # Create a fresh base system image

# # So this works
# #base_sysimage = SysImgBase.create_fresh_base_sysimage(["Random"])
# #base_sysimage = SysImgBase.create_fresh_base_sysimage()


#project = joinpath(dirname(@__DIR__), "examples/modjulia")
# sysimage_path = tempname() * ".dylib"
# base_sysimage = unsafe_string(Base.JLOptions().image_file),

#compile_sysimage(base_sysimage, sysimage_path, ["Mods"]; project)

# #create_sysimage_pkgcompiler(["Mods"]; sysimage_path, project, base_sysimage)
# #create_sysimage_pkgcompiler(["Mods"]; sysimage_path, project)

# @show stat(sysimage_path).size/1024/1024

# run(`julia --startup-file=no -J$sysimage_path --eval "import .Mods"`)


import Pkg.BinaryPlatforms: MacOS, Linux, Windows
import AppBundler: stage, PkgImage


import AppBundler.Stage: julia_download_url
import Pkg.BinaryPlatforms: Linux, Windows, MacOS


#src_dir = dirname(@__DIR__) # AppBundler itself

#src_dir = joinpath(dirname(@__DIR__), "examples/modjulia")


#rm(joinpath(DEPOT_PATH[1], "compiled/v1.11/Colors"), recursive=true, force=true)

#src_dir = joinpath(dirname(@__DIR__), "examples/sysimg")

#src_dir = joinpath(dirname(@__DIR__), "examples/glapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
src_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")
#src_dir = joinpath(dirname(@__DIR__), "examples/mousetrap")

if Sys.islinux()
    platform = Linux(Sys.ARCH)
elseif Sys.isapple()
    platform = MacOS(Sys.ARCH)
elseif Sys.iswindows()
    platform = Windows(Sys.ARCH)
end


#product_spec = PkgImage(src_dir; precompile = true, sysimg_packages = ["sysimg"])

#product_spec = PkgImage(src_dir; precompile = true, sysimg_packages = ["GtkApp"])
product_spec = PkgImage(src_dir; precompile = true, sysimg_packages = ["QMLApp"])
#product_spec = PkgImage(src_dir; precompile = true, sysimg_packages = ["Mods"])
stage(product_spec, platform, mktempdir(); cpu_target="native")
