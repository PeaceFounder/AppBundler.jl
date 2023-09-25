# Sets up julia direcotries

DEPOT_DIR = joinpath(tempdir(), "julia-depot")
push!(empty!(DEPOT_PATH), DEPOT_DIR)

# It would be prettier if there wouldn't be a need for a symlink
rm(joinpath(tempdir(), "julia-depot", "artifacts"), force=true)
symlink(realpath(ENV["JULIA_ARTIFACT_OVERRIDE"]), joinpath(tempdir(), "julia-depot", "artifacts"))

