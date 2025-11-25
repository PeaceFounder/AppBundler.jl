using PackageCompiler


project = joinpath(dirname(@__DIR__), "examples/sysimg")

sysimage_path = tempname()

PackageCompiler.create_sysimage(["sysimg"]; sysimage_path, project)
