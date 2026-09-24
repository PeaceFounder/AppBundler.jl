# MANUAL TESTS: Before every major release, manually verify that produced bundles 
# are functional on each platform. Small configuration errors in startup scripts or 
# missing post-configuration steps can silently break bundles without failing builds.

import AppBundler #: Snap, MSIX, DMG, bundle, JuliaImgBundle, JuliaCBundle

root_dir = dirname(dirname(@__DIR__))
build_dir = joinpath(root_dir, "build")
mkpath(build_dir)

# Nonprecompiled option is interesting to test on linux
# app_dir = joinpath(root_dir, "examples/modjulia")
# args = ["build", app_dir, "--build-dir=$build_dir", "-Dapp_name=modjuliauc", "--force", "--selfsign", "-Djuliaimg.precompile=false", "-Djuliaimg.incremental=true", "-Djuliaimg.sysimg=[]", "--debug"]
# AppBundler.main(args)

# Example with compiled sysimage and remaining modules precompiled
app_dir = joinpath(root_dir, "examples/modjulia")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign"]
AppBundler.main(args)

app_dir = joinpath(root_dir, "examples/QMLApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliaimg"]
AppBundler.main(args)

app_dir = joinpath(root_dir, "examples/QMLApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dapp_name=qmlappjc", "-Dbundler=juliac"]
AppBundler.main(args)

app_dir = joinpath(root_dir, "examples/CmdApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliaimg", "-Dapp_name=cmdappjuliaimg"]
AppBundler.main(args)

app_dir = joinpath(root_dir, "examples/CmdApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "-Dbundler=juliac", "-Dapp_name=cmdappjuliac"]
AppBundler.main(args)

