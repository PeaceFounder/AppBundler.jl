import Pkg
import TOML

function install_project_toml(uuid, pkginfo, destination)
    # Extract information from pkginfo
    project_dict = Dict(
        "name" => pkginfo.name,
        "uuid" => string(uuid),  # or use the package UUID if you have it
        "version" => string(pkginfo.version),
        "deps" => pkginfo.dependencies
    )

    # Convert UUIDs to strings for TOML
    exclude = ["Test"]
    deps_dict = Dict(name => string(uuid) for (name, uuid) in pkginfo.dependencies if name ∉ exclude)
    project_dict["deps"] = deps_dict

    # Write to Project.toml
    open(destination, "w") do io
        TOML.print(io, project_dict)
    end

    return
end

function retrieve_packages(packages_dir)

    mkpath(packages_dir)

    for (uuid, pkginfo) in Pkg.dependencies()
        if !(uuid in keys(Pkg.Types.stdlibs()))

            pkg_dir = joinpath(packages_dir, pkginfo.name)

            if !isdir(pkg_dir)
                cp(pkginfo.source, pkg_dir)
                if !isfile(joinpath(pkg_dir, "Project.toml"))
                    # We need to make a Project.toml from pkginfo
                    @warn "$(pkginfo.name) uses the legacy REQUIRE format. As a courtesy to AppBundler developers, please update it to use Project.toml."
                    install_project_toml(uuid, pkginfo, joinpath(pkg_dir, "Project.toml"))
                end
            else
                @info "$(pkginfo.name) already exists in $packages_dir"
            end
        end
    end

    return
end
