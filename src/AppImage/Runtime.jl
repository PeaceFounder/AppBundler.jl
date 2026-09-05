"""
    AppImageRuntime

Resolution of the AppImage runtime binary.

The runtime is a ~900 KB static-PIE ELF that mounts the appended squashfs and executes `AppRun`.
Unlike every other binary AppBundler depends on there is no jll for it yet: building one means
first packaging `libfuse` and `squashfuse`, neither of which exists in Yggdrasil. Until
`AppImageRuntime_jll` is registered, point AppBundler at a runtime you obtained yourself.
"""
module AppImageRuntime

"""
Architectures the upstream project publishes a runtime for.
"""
const ARCHITECTURES = [:x86_64, :i686, :aarch64, :armhf]

const RELEASES = "https://github.com/AppImage/type2-runtime/releases"

"""
    resolve(arch::Symbol; runtime = nothing, allow_jll = true) -> String

Return the path of the AppImage runtime for `arch`.

An explicit `runtime` path wins. Otherwise `AppImageRuntime_jll` is used when the user has it
installed — it is looked up with a guarded import rather than declared as a dependency, since the
package is not registered yet. Failing both, an error explains how to supply one.
"""
function resolve(arch::Symbol; runtime::Union{String, Nothing} = nothing, allow_jll::Bool = true)

    if !isnothing(runtime) && !isempty(runtime)
        isfile(runtime) ||
            error("The AppImage runtime `$runtime` does not exist. Set `appimage_runtime` in " *
                  "LocalPreferences.toml, or pass `runtime = <path>` to `AppImage`.")
        return runtime
    end

    if allow_jll
        from_jll = jll_runtime(arch)
        isnothing(from_jll) || return from_jll
    end

    arch in ARCHITECTURES ||
        error("No AppImage runtime exists for `$arch`. Upstream publishes: " *
              join(ARCHITECTURES, ", ") * ".")

    error("""
          No AppImage runtime available for $arch.

          AppBundler uses `AppImageRuntime_jll` when it is installed. That package is not yet
          registered, so until it is, obtain a runtime and point AppBundler at it:

              # LocalPreferences.toml
              [AppBundler]
              appimage_runtime = "/path/to/runtime-$arch"

          or pass `runtime = "/path/to/runtime-$arch"` to `AppImage`. Upstream publishes signed
          runtimes at $RELEASES — prefer a dated tag over `continuous` so builds stay reproducible.
          """)
end

"""
    jll_runtime(arch::Symbol) -> Union{String, Nothing}

Look for `AppImageRuntime_jll` in the active environment, returning `nothing` when it is absent.

The package is resolved by name through the active environment rather than by UUID, because it is
not registered yet and its UUID is therefore not knowable here. Once it is registered this starts
working with no change.

A jll provides the artifact for the *host* platform, so it only answers for a native build.
Bundling for another architecture still needs an explicit runtime path.
"""
function jll_runtime(arch::Symbol)

    arch === Sys.ARCH || return nothing

    return try
        pkgid = Base.identify_package("AppImageRuntime_jll")
        isnothing(pkgid) && return nothing

        jll = Base.require(pkgid)
        path = Base.invokelatest(getproperty, jll, :runtime_path)

        isfile(path) ? path : nothing
    catch
        nothing
    end
end

end
