#ToDo: Need to refactor this using the AppBundler's new API
# No need for the github workflow


# examples.jl - Test suite for AppBundler example applications
#
# Usage:
#   julia --project=. test/examples.jl
#   julia --project=. test/examples.jl --target-platform=all --compiled-modules=no
#
# Tests QML, GTK, OpenGL, Mousetrap, Blink and Makie app bundling by installing GitHub workflows
# and executing build scripts from examples/*/meta/build.jl

# run theese examples with
# julia --project=. test/examples.jl 
# julia --project=. test/examples.jl --target-platform=all --compiled-modules=no 

using AppBundler
using Test

build_dir = joinpath(@__DIR__, "../build")
args(app_dir) = ["build", app_dir, "--build-dir=$build_dir", "--force"]

@testset "GtkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/GTKApp")
    AppBundler.main(args(app_dir))
end    

@testset "GLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/GLApp")
    AppBundler.main(args(app_dir))
end    

@testset "QMLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
    AppBundler.main(args(app_dir))
end    

# @testset "Mousetrap" begin
#     app_dir = joinpath(dirname(@__DIR__), "examples/Mousetrap")
#     AppBundler.main(args(app_dir))
# end 

@testset "BlinkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/BlinkApp")
    AppBundler.main(args(app_dir))
end 

@testset "MakieApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/MakieApp")
    AppBundler.main(args(app_dir))
end 

@testset "ElectronApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/ElectronApp")
    AppBundler.main(args(app_dir))
end 

@testset "CmdApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
    AppBundler.main(args(app_dir))
end 

@testset "ModJulia" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
    AppBundler.main(args(app_dir))
end 
