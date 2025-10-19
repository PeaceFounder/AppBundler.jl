using Random: RandomDevice
using Base64
using rcodesign_jll: rcodesign
using TOML

function get_version(app_dir)
    
    project = joinpath(app_dir, "Project.toml")

    if isfile(project)
        try
            return TOML.parsefile(project)["version"] 
        catch
            error("Parsing of $project file failed")
        end
    else
        error("App project file does not exist at $project")
    end
end


function generate_macos_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)
    
    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))
        
    destination = joinpath(root, "meta/dmg/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))

    run(`$(rcodesign()) generate-self-signed-certificate --person-name="$person_name" --p12-file="$destination" --p12-password="$password" --country-name=$country --validity-days="$validity_days"`)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/macos/certificate.pfx; To use certificate set certificate password with environment variable:

        export MACOS_PFX_PASSWORD="$password"
    """)

    ENV["MACOS_PFX_PASSWORD"] = password

    return
end

function generate_windows_signing_certificate(root; person_name = "AppBundler", country = "XX", validity_days = 365, force=false)

    password = Base64.base64encode(rand(RandomDevice(), UInt8, 16))

    destination = joinpath(root, "meta/msix/certificate.pfx")

    if isfile(destination) && !force
        error("Certificate at $destination alredy exists. Use `force=true` to overwrite it")
    end

    mkpath(dirname(destination))
    
    MSIXPack.generate_self_signed_certificate(destination; password, name = person_name, country, validity_days)

    println("""
    The certificate is encrypted with a strong encryption algorithm and stored at meta/windows/certificate.pfx; To use certificate set certificate password with environment variable:

        export WINDOWS_PFX_PASSWORD="$password"
    """)
    
    ENV["WINDOWS_PFX_PASSWORD"] = password

    return
end

# instantiation of self signed keys could be done at a seperate command!
function install_github_workflow(; root = dirname(Base.ACTIVE_PROJECT[]), force = false)

    if !isfile(joinpath(root, "Project.toml"))
        error("It appears $root does not contain a valid Julia project")
    else
        parameters = get_bundle_parameters(joinpath(root, "Project.toml"))
    end

    mkpath(joinpath(root, ".github/workflows"))

    cp(joinpath(dirname(@__DIR__), "recipes/workflows/GitHub.yml"), joinpath(root, ".github/workflows/Release.yml"); force)


    install(joinpath(dirname(@__DIR__), "recipes/workflows/build.jl"), joinpath(root, "meta/build.jl"); parameters, force)
   
    println("""
    Setup done. You may now commit the workflow to the repo that will automatically build artifiacts and attach for new GitHub releases. You can also test builds before releasing. See documentation for more.

    You may now want to add signing certificates for macos and windows builds at `meta/dmg/certificate.pfx` and `meta/msix/certificate.pfx` accordingly. You can generate self signing certificates runing `generate_signing_certiifcates()`

    To test the workflow locally run meta/build.jl. See extra options to customize your build there. 
    """)

    return
end


function generate_signing_certificates(; root = dirname(Base.ACTIVE_PROJECT[]), person_name = "AppBundler", country = "XX", validity_days = 365, force = false)

    generate_macos_signing_certificate(root; person_name, country, validity_days, force)
    generate_windows_signing_certificate(root; person_name, country, validity_days, force)

    return
end

function isext(filename::String, ext::String)
    # Base case: if the filename is empty or doesn't have the extension, return false.
    if isempty(filename) || !endswith(filename, ext)
        return false
    end
    
    # If the current filename ends with the desired extension, return true.
    if endswith(filename, ext)
        return true
    end
    
    # Otherwise, recurse after stripping the current extension.
    root, _ = splitext(filename)
    return isext(root, ext)
end

function is_windows_compatible(filename::String; path_length_threshold)
    # Check for invalid characters

    if occursin(r"[<>:\"\\\|?*\x00-\x1F]", filename) || occursin(r"[\x7F-\x9F]", filename)
        @warn "$(filename) contains invalid characters for Windows."
        return false
    end

    # if occursin(r"[\\/:*?\"<>|]", filename)
    #     @warn "$filename contains invalid characters for Windows.\n"
    #     return false
    # end

    # Check for reserved names
    reserved_names = ["CON", "PRN", "AUX", "NUL"]
    reserved_names_with_numbers = [string(name, i) for name in ["COM", "LPT"] for i in 1:9]
    append!(reserved_names, reserved_names_with_numbers)

    basename_no_ext = splitext(basename(filename))[1]
    if uppercase(basename_no_ext) in reserved_names
        @warn "$filename is a reserved name in Windows.\n"
        return false
    end

    # # Check filename length (Windows max path is 260 characters)
    if length(filename) > path_length_threshold
        @warn "$filename exceeds Windows max path length.\n"
        return false
    end

    return true
end

function ensure_windows_compatability(src_dir::String; path_length_threshold::Int = 260, skip_long_paths::Bool = false, skip_symlinks = false)

    error_paths = []
    
    max_length = 0

    for (root, dirs, files) in walkdir(src_dir; follow_symlinks=false)
        for file in files
            filepath = joinpath(root, file)
            rel_path = relpath(filepath, src_dir)

            if skip_symlinks && islink(filepath)
                rm(filepath)
                println("Removed symlink: $filepath")
                continue
            end
            
            if skip_long_paths && length(rel_path) > path_length_threshold
                rm(filepath)
                continue
            end

            if Sys.isunix() && !is_windows_compatible(rel_path; path_length_threshold)
                push!(error_paths, rel_path)
                error("Aborting due to Windows-incompatible filename.")
            end

            if length(rel_path) > max_length
                max_length = length(rel_path)
            end
        end

        for dir in dirs
            dirpath = joinpath(root, dir)
            if skip_symlinks && islink(dirpath)
                rm(dirpath)
                println("Removed symlink: $dirpath")
            end
        end
    end

    # removing empty direcotories
    for (root, dirs, files) in walkdir(src_dir, topdown=false)
        for dir in dirs
            path = joinpath(root, dir)
            if isempty(readdir(path))
                rm(path)
            end
        end
    end

    @info "Maximum relative path length is $max_length"

    if length(error_paths) > 0
        #@warn "$(length(error_paths)) errors detected"
        error("$(length(error_paths)) errors detected")
    end

    return
end


function get_path(prefix::Vector, suffix::Vector; dir = false, warn = true)

    for i in prefix
        for j in suffix
            fname = joinpath(i, j)
            if isfile(fname) || (dir && isdir(fname))
                return fname
            end
        end
    end
    
    if warn
        @warn "No option for $suffix found"
    end

    return
end

get_path(prefix::String, suffix::String; kwargs...) = get_path([prefix], [suffix]; kwargs...)
get_path(prefix::String, suffix::Vector; kwargs...) = get_path([prefix], suffix; kwargs...)
get_path(prefix::Vector, suffix::String; kwargs...) = get_path(prefix, [suffix]; kwargs...)
