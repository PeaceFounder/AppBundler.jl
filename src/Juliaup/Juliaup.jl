"""
    Juliaup

Publishing of AppBundler-produced distributions through `juliaup`.

`juliaup` downloads from whatever host `JULIAUP_SERVER` points at, so distributing a bundled Julia
through it needs no fork and no dedicated infrastructure — only a handful of static files. This
module writes them: the per-target version databases and the `*DBVERSION` pointer files that tell a
client which database to fetch.

See the [Juliaup](@ref) section of the documentation for the full workflow.
"""
module Juliaup

using ..AppBundler
using ..AppBundler: JuliaImg

include("VersionDB.jl")
include("Distribution.jl")

export JuliaupDistribution, publish, install_wrappers

end
