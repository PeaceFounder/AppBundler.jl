using AppBundler
using Test

build_dir = joinpath(@__DIR__, "../build")
args(app_dir) = ["build", app_dir, "--build-dir=$build_dir", "--force", "--selfsign", "--target-bundle=appimage"]

@testset "GtkApp" begin
    app_dir = joinpath(dirname(@__DIR__), "examples/GTKApp")
    AppBundler.main(args(app_dir))
end    

# # @testset "CmdApp" begin
# #     app_dir = joinpath(dirname(@__DIR__), "examples/CmdApp")
# #     AppBundler.main(args(app_dir))
# # end 

# @testset "ModJulia" begin
#     app_dir = joinpath(dirname(@__DIR__), "examples/modjulia")
#     AppBundler.main(args(app_dir))
# end 
