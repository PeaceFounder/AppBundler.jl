using Test

import AppEnv

import Base: PkgId, PkgOrigin

@testset "pkgorigins" begin

    pkgorigins = Dict{PkgId, PkgOrigin}()
    AppEnv.collect_pkgorigins!(pkgorigins)

    origin_path = tempname()
    AppEnv.save_pkgorigins(origin_path, pkgorigins)

    loaded_pkgorigins = Dict{PkgId, PkgOrigin}()
    AppEnv.load_pkgorigins!(loaded_pkgorigins, origin_path)

    # Test: Compare all entries
    @test length(pkgorigins) == length(loaded_pkgorigins)
    for (pkg_id, origin) in pkgorigins
        loaded = loaded_pkgorigins[pkg_id]
        @test origin.path == loaded.path && origin.version == loaded.version
    end

end

