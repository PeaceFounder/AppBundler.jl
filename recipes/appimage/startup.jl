# Startup file used when `appimage_depot = "julia"`.
#
# The stock startup.jl calls AppEnv.init(), which replaces DEPOT_PATH outright — every
# set_depot_path_* in AppEnv begins with `empty!(DEPOT_PATH)`. For sites that want the user's real
# ~/.julia depot, set up the load path for the bundled stdlib but leave the depot as Julia found
# it, appending the bundled share/julia so the shipped packages stay resolvable.

if isdir(joinpath(last(DEPOT_PATH), "compiled/v$(VERSION.major).$(VERSION.minor)", "AppEnv")) || any(i -> i.name == "AppEnv", keys(Base.loaded_modules))
    import AppEnv
else
    include(joinpath(Sys.STDLIB, "AppEnv/src/AppEnv.jl"))
end

let config_path = joinpath(dirname(Sys.BINDIR), "config"),
    index_path = joinpath(dirname(Sys.BINDIR), "index")

    (; stdlib_project_name) = AppEnv.load_config(config_path)

    AppEnv.set_load_path!(Base.LOAD_PATH; stdlib_project_name)

    bundled_depot = joinpath(dirname(Sys.BINDIR), "share/julia")
    bundled_depot in Base.DEPOT_PATH || push!(Base.DEPOT_PATH, bundled_depot)

    isfile(index_path) && AppEnv.load_pkgorigins!(Base.pkgorigins, index_path)
end

if isinteractive() && !isempty("{{MODULE_NAME}}") && isempty(ARGS)
    println("No arguments provided. To display help, use:")
    julia = relpath(joinpath(Sys.BINDIR, "julia"), pwd())
    println("  $julia --eval \"using {{MODULE_NAME}}\" --help")
end
