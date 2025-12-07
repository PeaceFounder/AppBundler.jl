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


@testset "config" begin

    runtime_mode = "SANDBOX"
    stdlib_project_name = "MyApp"
    bundle_identifier = "org.appbundler.myapp"
    app_name = "MyApp"
    
    config_path = tempname()

    AppEnv.save_config(config_path; runtime_mode, stdlib_project_name, bundle_identifier, app_name)
    loaded = AppEnv.load_config(config_path)

    @test loaded.runtime_mode == runtime_mode
    @test loaded.stdlib_project_name == stdlib_project_name
    @test loaded.bundle_identifier == bundle_identifier
    @test loaded.app_name == app_name

end
