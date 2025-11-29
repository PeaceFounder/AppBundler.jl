module QMLApp

using QML

global _PROPERTIES::JuliaPropertyMap

# ToDo: update this script
function fill_stdlib_pkgorigins!()
    stdlib_dir = Sys.STDLIB
    
    uuid_regex = r"^uuid\s*=\s*\"([a-f0-9\-]+)\""mi
    version_regex = r"^version\s*=\s*\"([^\"]+)\""mi
    
    for name in readdir(stdlib_dir)
        pkg_path = joinpath(stdlib_dir, name)
        
        # Skip if not a directory
        isdir(pkg_path) || continue
        
        # Look for Project.toml
        project_file = joinpath(pkg_path, "Project.toml")
        isfile(project_file) || continue
        
        # Read file content
        content = read(project_file, String)
        
        # Extract uuid
        uuid_match = match(uuid_regex, content)
        uuid_match === nothing && continue
        uuid = Base.UUID(uuid_match[1])
        
        # Extract version (optional)
        version_match = match(version_regex, content)
        version = version_match === nothing ? nothing : VersionNumber(version_match[1])
        
        # Find the module file path (typically src/<name>.jl)
        module_file = joinpath(pkg_path, "src", "$name.jl")
        if !isfile(module_file)
            # Skip if module file doesn't exist
            continue
        end
        
        # Create PkgId and PkgOrigin
        pkg_id = Base.PkgId(uuid, name)
        pkg_origin = Base.PkgOrigin(module_file, nothing, version)
        
        # Add to pkgorigins
        Base.pkgorigins[pkg_id] = pkg_origin
    end
    
    return
    #return Base.pkgorigins
end


function julia_main()::Cint

    fill_stdlib_pkgorigins!()

    global _PROPERTIES = JuliaPropertyMap(
        "text" => "Hello World Again!",
        "count" => 16
    )

    loadqml(joinpath(Base.pkgdir(@__MODULE__), "src/App.qml"); _PROPERTIES)
    exec()

    return 0
end

function (@main)(ARGS)
    return julia_main()
end

export main


end # module QMLApp
