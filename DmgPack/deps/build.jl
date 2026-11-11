using Pkg
using Conda

Conda.add("ds_store", channel="conda-forge")

# Force Julia to use the Conda Python
ENV["PYTHON"] = ""
Pkg.build("PyCall")

# Print confirmation message
println("Python dependencies installed successfully via Conda!")

# Launcher stub installation
import Pkg
using Base.BinaryPlatforms: Platform

const artifacts_toml = joinpath(dirname(dirname(Base.find_package("AppBundlerUtils_jll"))), "Artifacts.toml")

for arch in ["aarch64", "x86_64"]
    platform = Platform(arch, "macos")
    artifacts = Pkg.Artifacts.select_downloadable_artifacts(artifacts_toml; platform)["AppBundlerUtils"]
    path = Pkg.Artifacts.ensure_artifact_installed("AppBundlerUtils", artifacts, artifacts_toml; platform)
end
