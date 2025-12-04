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

@testset "QMLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/QMLApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/QMLApp/meta/build.jl")
end    

@testset "GtkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/GTKApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/GtkApp/meta/build.jl")
end    

@testset "GLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/GLApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/GLApp/meta/build.jl")
end    

@testset "Mousetrap" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/Mousetrap")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/Mousetrap/meta/build.jl")
end 

@testset "BlinkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/BlinkApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/BlinkApp/meta/build.jl")
end 

@testset "MakieApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/MakieApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/MakieApp/meta/build.jl")
end 

@testset "ElectronApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/ElectronApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/ElectronApp/meta/build.jl")
end 

@testset "CmdApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/CmdApp/meta/build.jl")
end 

@testset "ModJulia" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/modjulia/meta/build.jl")
end 
