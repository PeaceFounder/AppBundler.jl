"""
    get_julia_version(source::String) -> VersionNumber

Extract the Julia version from Manifest.toml if it exists, otherwise return the current Julia version.
"""
function get_julia_version(source::String)
    manifest_file = joinpath(source, "Manifest.toml")
    
    try
        manifest_dict = TOML.parsefile(manifest_file)
        return VersionNumber(manifest_dict["julia_version"])
    catch
        @info "Reading Julia from Manifest.toml failed. Using host Julia version $VERSION instead"
        return VERSION
    end
end


@kwdef struct PkgImage
    source::String
    precompile::Bool = true
    incremental::Bool = true
    julia_version::VersionNumber = get_julia_version(source)
end

PkgImage(source; precompile = true, incremental = true, julia_version = get_julia_version(source)) = PkgImage(; source, precompile, incremental, julia_version)


get_parameters(product::PkgImage) = get_bundle_parameters("$(product.source)/Project.toml")


function get_module_name(source_dir)
    
    if isfile(joinpath(source_dir), "Project.toml")
        toml_dict = TOML.parsefile(joinpath(source_dir,"Project.toml"))
        return get(toml_dict, "name", "MainEntry")
    else
        @warn "Returning source directory name as last resort for module name as Project.toml not found"
        return basename(source_dir)
    end

end

function override_startup_file(source, destination; parameters = Dict())

    user_startup_file = joinpath(source, "meta/startup.jl")
    if isfile(user_startup_file)
        startup_file = user_startup_file
    else
        startup_file = joinpath(dirname(@__DIR__), "recipes/startup.jl")
    end
    #cp(startup_file, destination, force=true)
    install(startup_file, destination; parameters, force = true)

    return
end


"""
    validate_cross_compilation(product::PkgImage, platform::AbstractPlatform) -> Bool

Validate whether cross-compilation is supported for the given platform combination.
Throws descriptive errors for unsupported combinations.

# Arguments
- `product::PkgImage`: The package configuration
- `platform::AbstractPlatform`: Target platform

# Returns
- `Bool`: true if compilation is supported

# Throws
- `ArgumentError`: If cross-compilation is not supported
"""
function validate_cross_compilation(platform::AbstractPlatform)
    
    # Windows compilation
    if platform isa Windows
        if !Sys.iswindows()
            throw(ArgumentError("Cross-compilation to Windows from $(Sys.KERNEL) is not supported"))
        end
        return true
    end
    
    # macOS compilation
    if platform isa MacOS
        if !Sys.isapple()
            throw(ArgumentError("Cross-compilation to macOS from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on macOS
        if Sys.ARCH == :x86_64 && arch(platform) == :aarch64
            throw(ArgumentError("Cannot compile aarch64 binaries from x86_64 macOS"))
        end
        return true
    end
    
    # Linux compilation
    if platform isa Linux
        if !Sys.islinux()
            throw(ArgumentError("Cross-compilation to Linux from $(Sys.KERNEL) is not supported"))
        end
        
        # Check architecture compatibility on Linux
        if Sys.ARCH !== arch(platform)
            throw(ArgumentError("Cross-compilation across architectures not supported ($(Sys.ARCH) -> $(arch(platform)))"))
        end
        return true
    end
    
    throw(ArgumentError("Unsupported target platform: $(typeof(platform))"))
end


"""
    get_cpu_target(platform::AbstractPlatform) -> String

Get the appropriate CPU target string for the given platform architecture.

# Arguments
- `platform::AbstractPlatform`: Target platform

# Returns
- `String`: CPU target specification for Julia compilation
"""
function get_cpu_target(platform::AbstractPlatform)
    target_arch = arch(platform)
    
    return if target_arch == :x86_64
        "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)"
    elseif target_arch == :aarch64
        "generic;neoverse-n1;cortex-a76;apple-m1"
    else
        @warn "Unknown architecture $target_arch, using generic CPU target"
        "generic;"
    end
end


function stage(product::PkgImage, platform::AbstractPlatform, destination::String; module_name = get_module_name(product.source))

    if product.precompile
        validate_cross_compilation(platform)
    end

    #rm(destination, recursive=true, force=true)
    #mkpath(dirname(destination))

    @info "Downloading Julia for $platform"
    retrieve_julia(platform, "$destination"; version = product.julia_version)

    retrieve_packages(product.source, "$destination/share/julia/packages")
    copy_app(product.source, "$destination/share/julia/packages/$module_name")

    retrieve_artifacts(platform, "$destination/share/julia/packages", "$destination/share/julia/artifacts")

    # Perhaps the LOAD_PATH could be manipulated only for the compilation
    override_startup_file(product.source, "$destination/etc/julia/startup.jl"; parameters = Dict("MODULE_NAME" => module_name))

    if product.precompile
        @info "Precompiling"

        if !product.incremental
            rm("$destination/share/julia/compiled", recursive=true)
        end

        withenv("JULIA_PROJECT" => "$destination/share/julia/packages/$module_name", "USER_DATA" => mktempdir(), "JULIA_CPU_TARGET" => get_cpu_target(platform)) do

            julia = "$destination/bin/julia"
            run(`$julia --eval "@show LOAD_PATH; @show DEPOT_PATH; popfirst!(LOAD_PATH); popfirst!(DEPOT_PATH); import $module_name"`)
        end

    else
        @info "Precompilation disabled. Precompilation will occur on target system at first launch."
    end

    @info "App staging completed successfully"
    @info "Staged app available at: $destination"
    @info "Launch it with bin/julia -e \"using $module_name\""

    return
end
