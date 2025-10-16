# examples.jl - Test suite for AppBundler example applications
#
# Usage:
#   julia --project=. test/examples.jl
#   julia --project=. test/examples.jl --target-platform=all --compiled-modules=no
#
# Tests QML, GTK, OpenGL, and Mousetrap app bundling by installing GitHub workflows
# and executing build scripts from examples/*/meta/build.jl

# run theese examples with
# julia --project=. test/examples.jl 
# julia --project=. test/examples.jl --target-platform=all --compiled-modules=no 

using AppBundler
using Test

@testset "QMLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/qmlapp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/qmlapp/meta/build.jl")
end    

@testset "GtkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/gtkapp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/gtkapp/meta/build.jl")
end    

@testset "GLApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/glapp")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/glapp/meta/build.jl")
end    

@testset "Mousetrap" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/mousetrap")
    AppBundler.install_github_workflow(; root = app_dir, force = true)
    @eval include("../examples/mousetrap/meta/build.jl")
end 
