# Main entry points for AppBundler development.
# Run `just` to list them.

julia := "julia --startup-file=no"

default:
    @just --list

# Install dependencies, including the Python `ds_store` module via Conda
instantiate:
    {{julia}} --project=. -e 'using Pkg; Pkg.instantiate()'
    {{julia}} --project=. deps/build.jl

# Run the test suite
test:
    {{julia}} --project=. -e 'using Pkg; Pkg.test()'

# Run the AppImage tests alone
test-appimage:
    {{julia}} --project=. test/appimage.jl

# Run the AppImage end to end test against a real runtime
# APPIMAGE_RUNTIME must point at a runtime from
# https://github.com/AppImage/type2-runtime/releases
test-appimage-e2e:
    {{julia}} --project=. test/appimage_e2e.jl

# Build the documentation
docs:
    {{julia}} --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path = pwd())); Pkg.instantiate()'
    {{julia}} --project=docs docs/make.jl

# Build an AppImage from an example app
appimage app="examples/CmdApp":
    {{julia}} --project=. -m AppBundler build {{app}} --build-dir=build --target-bundle=appimage --force

# Remove build outputs
clean:
    rm -rf build docs/build
