
ENV["BUNDLE_IDENTIFIER"] = "{{BUNDLE_IDENTIFIER}}"
ENV["APP_NAME"] = "{{APP_NAME}}"

ENV["ROOT"] = @__DIR__ 
ENV["JULIA"] = joinpath(Sys.BINDIR, "julia.exe") 
ENV["JULIA_DEBUG"] = "loading"

module WINDOWS_STARTUP

const debug = {{DEBUG}}

const WITH_SPLASH_SCREEN={{WITH_SPLASH_SCREEN}}

function get_user_directory()

    BASE_DIR = dirname(dirname(Sys.BINDIR))

    if basename(dirname(BASE_DIR)) == "WindowsApps"
        
        parts = split(basename(BASE_DIR), "_")
        _basename = first(parts) * "_" * last(parts)
        
        base_dir = joinpath(ENV["LOCALAPPDATA"], "Packages", _basename)

        return joinpath(base_dir, "LocalState")
    else
        # This is the case when app is installed with Add-AppxPackage 
        # It would likelly fail in UWP container environment. For such
        # situation a command line app could be made and bundled together
        # to get a proper path. An alternative of using a tempdir may also work.

        for dirname in readdir(joinpath(ENV["LOCALAPPDATA"], "Packages"))

            parts = split(basename(dirname), "_")

            if first(parts) == ENV["BUNDLE_IDENTIFIER"]

                _basename = first(parts) * "_" * last(parts)
                base_dir = joinpath(ENV["LOCALAPPDATA"], "Packages", _basename)
                return joinpath(base_dir, "LocalState")
            end
        end
    end    

    error("Could not infer a user data direcotry. Check correctness of the family name or set USER_DATA environment direcotry manually.")
end

if !("USER_DATA" in keys(ENV))
    ENV["USER_DATA"] = get_user_directory()
end

@assert isdir(ENV["USER_DATA"]) "User data directory USER_DATA = $USER_DATA does not exist."

if !debug # In case od debug the output is better being shown on the screen
    logfile = open(joinpath(ENV["USER_DATA"], "startup.log"), "w")
    redirect_stdout(logfile)
    redirect_stderr(logfile)
    println("LOGFILE INITIALIZED")
end

println("User data directory: " * ENV["USER_DATA"]) 

Base.ACTIVE_PROJECT[] = joinpath(@__DIR__, ENV["APP_NAME"])

empty!(LOAD_PATH)
append!(LOAD_PATH, [
    joinpath(@__DIR__, "packages"),
    "@",
    "@stdlib"
])

empty!(DEPOT_PATH)
append!(DEPOT_PATH, [
    joinpath(ENV["USER_DATA"], "cache"),
    @__DIR__
])
        
# Setting up environment variables in case one starts subproceeses with `run`
ENV["JULIA_PROJECT"] = Base.ACTIVE_PROJECT[]
ENV["JULIA_DEPOT_PATH"] = join(DEPOT_PATH, ";")
ENV["JULIA_LOAD_PATH"] = join(LOAD_PATH, ";")

println("DEPOT_PATH:")
for i in DEPOT_PATH
    println("\t$i")
end

println("LOAD_PATH:")
for i in LOAD_PATH
    println("\t$i")
end

PRECOMPILED = joinpath(ENV["USER_DATA"], "cache", "precompiled")

if !WINDOWS_STARTUP.debug
    rm(dirname(PRECOMPILED), recursive=true, force=true)
end

if WITH_SPLASH_SCREEN && ( !(isdir(joinpath(@__DIR__, "compiled")) || isfile(PRECOMPILED)) )

    @info "Precompiling..."

    # 3D acceleration needs to be enabled in windows for OpenGL
    if WITH_SPLASH_SCREEN
            
        # include("startup/SplashScreen/SplashScreen.jl")
        # splash_window = SplashScreen.create_splash_window()
        # include("startup/precompile.jl")
        # SplashScreen.close_window(splash_window)

        include("startup/configure.jl")
        touch(PRECOMPILED)
    end
end

@info "Loading startup modules"
include("startup/precompile.jl")
@info "Loading succcesfull"

end

if !WINDOWS_STARTUP.debug
    redirect_stdout()
    redirect_stderr()

    include(joinpath(@__DIR__, "startup", "init.jl")) # One may set up a logging there
end
include(joinpath(@__DIR__, ENV["APP_NAME"], "main.jl"))
