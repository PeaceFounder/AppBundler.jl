# MANUAL TESTS: Before every major release, manually verify that produced bundles 
# are functional on each platform. Small configuration errors in startup scripts or 
# missing post-configuration steps can silently break bundles without failing builds.

import AppBundler #: Snap, MSIX, DMG, bundle, JuliaImgBundle, JuliaCBundle

build_dir = joinpath(dirname(@__DIR__), "build")
mkpath(build_dir)

# Nonprecompiled option is interesting to test on linux
app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
args = ["build", app_dir, "--build-dir=$build_dir", "--target-name=modjulia-uncompiled", "--force", "--selfsign", "-Djuliaimg_precompile=false"]
AppBundler.main(args)

# Example with compiled sysimage and remaining modules precompiled
app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign"]
AppBundler.main(args)

app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "--target-name=qmlapp-juliaimg", "-Dbundler=\"juliaimg\""]
AppBundler.main(args)

app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "--target-name=qmlapp-juliac", "-Dbundler=\"juliac\""]
AppBundler.main(args)

app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
args = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign"]
AppBundler.main(args)
