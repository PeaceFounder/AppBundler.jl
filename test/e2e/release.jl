# MANUAL TESTS: Before every major release, manually verify that produced bundles 
# are functional on each platform. Small configuration errors in startup scripts or 
# missing post-configuration steps can silently break bundles without failing builds.

import AppBundler #: Snap, MSIX, DMG, bundle, JuliaImgBundle, JuliaCBundle

root_dir = dirname(dirname(@__DIR__))
build_dir = joinpath(root_dir, "build")
mkpath(build_dir)

# # Nonprecompiled option is interesting to test on linux
# app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
# args = ["build", app_dir, "--build-dir=$build_dir", "--target-name=modjulia-uncompiled", "--force", "--selfsign", "-Djuliaimg_precompile=false", "-Djuliaimg_incremental=true", "-Djuliaimg_sysimg=[]"]
# AppBundler.main(args)

# Example with compiled sysimage and remaining modules precompiled
# app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign"]
# AppBundler.main(args)

# app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "--target-name=qmlapp-juliaimg", "-Dbundler=\"juliaimg\""]
# AppBundler.main(args)

# app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "--target-name=qmlapp-juliac", "-Dbundler=\"juliac\""]
# AppBundler.main(args)


app_dir = joinpath(root_dir, "examples/CmdApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliaimg"]
AppBundler.main(args)

# app_dir = joinpath(root_dir, "examples/CmdApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliaimg", "--debug", "-Dapp_name=cmdapp-snap-juliaimg"]
# AppBundler.main(args)

# app_dir = joinpath(root_dir, "examples/CmdApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliaimg", "--target-bundle=appimage", "--debug", "-Dapp_name=cmdapp-appimage-juliaimg"]
# AppBundler.main(args)

# app_dir = joinpath(root_dir, "examples/CmdApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliac", "--debug", "-Dapp_name=cmdapp-snap-juliac"]
# AppBundler.main(args)

# app_dir = joinpath(root_dir, "examples/CmdApp")
# args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliac", "--target-bundle=appimage", "--debug", "-Dapp_name=cmdapp-appimage-juliac"]
# AppBundler.main(args)
