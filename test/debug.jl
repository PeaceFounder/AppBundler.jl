using AppBundler

project_dir = joinpath(dirname(@__DIR__), "examples/GLApp")
target_name = "glapp"

args = ["-Djuliaimg.precompile=false", "-Dwindowed=true", "-Dmsix.bootstrapper=true"]

#AppBundler.print_preferences(args; project_dir)
AppBundler.print_overrides(project_dir)
