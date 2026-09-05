# Main entry points for AppBundler development.
# Run `just` to list them.

julia := "julia --startup-file=no"

default:
    @just --list

# Install the project's dependencies, including the Python `ds_store` module via Conda
instantiate:
    {{julia}} --project=. -e 'using Pkg; Pkg.instantiate()'
    {{julia}} --project=. deps/build.jl

# Run the test suite
test:
    {{julia}} --project=. -e 'using Pkg; Pkg.test()'

# Run the juliaup tests alone
test-juliaup:
    {{julia}} --project=. test/juliaup.jl
    {{julia}} --project=. test/tarball.jl

# Run the juliaup end to end test against a real juliaup client over loopback HTTP
test-juliaup-e2e:
    {{julia}} --project=. test/juliaup_e2e.jl

# Run the example bundles as well as the test suite
test-all:
    JULIA_RUN_EXAMPLES=true JULIA_RUN_JULIAUP_E2E=true {{julia}} --project=. -e 'using Pkg; Pkg.test()'

# Build the documentation, including llms.txt and llms-full.txt
docs:
    {{julia}} --project=docs -e 'using Pkg; Pkg.develop(PackageSpec(path = pwd())); Pkg.instantiate()'
    {{julia}} --project=docs docs/make.jl

# Serve the built documentation locally
docs-serve: docs
    {{julia}} -e 'using Sockets; run(`python3 -m http.server -d docs/build 8000`)'

# Build a tarball for the current platform from an example app
tarball app="examples/GtkApp":
    {{julia}} --project=. -m AppBundler build {{app}} --build-dir=build --target-bundle=tarball --force

# Publish a juliaup site for an example app into ./site
juliaup app="examples/GtkApp":
    {{julia}} --project=. -m AppBundler juliaup {{app}} --build-dir=site --no-mirror

# Remove build outputs
clean:
    rm -rf build site docs/build
