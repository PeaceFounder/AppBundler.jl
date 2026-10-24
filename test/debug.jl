using AppBundler

project_dir = joinpath(dirname(@__DIR__), "examples/GLApp")
target_name = "glapp"

#args = ["-Djuliaimg.precompile=false", "-Dwindowed=true", "-Dmsix.bootstrapper=true"]

#AppBundler.print_preferences(args; project_dir)
#AppBundler.print_overrides(project_dir)

#AppBundler.print_status(project_dir; args)
#AppBundler.main_status(project_dir, ["--files"])

AppBundler.main_status(project_dir, ["--preferences"])
AppBundler.main_status(project_dir, ["--files"])
