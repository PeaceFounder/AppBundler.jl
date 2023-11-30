ENV["BUNDLE_IDENTIFIER"] = "{{BUNDLE_IDENTIFIER}}"
ENV["APP_NAME"] = "{{APP_NAME}}"

ENV["ROOT"] = dirname(dirname(Sys.BINDIR))
ENV["JULIA"] = joinpath(Sys.BINDIR, "julia.exe") 

module WINDOWS_STARTUP

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

logfile = open(joinpath(ENV["USER_DATA"], "startup.log"), "w")
redirect_stdout(logfile)
redirect_stderr(logfile)

#import Dates
println("LOGFILE INITIALIZED")

popfirst!(DEPOT_PATH)
pushfirst!(DEPOT_PATH, ENV["ROOT"])
pushfirst!(DEPOT_PATH, joinpath(ENV["USER_DATA"], "cache"))
ENV["JULIA_DEPOT_PATH"] = join(DEPOT_PATH, ";")

pushfirst!(LOAD_PATH, joinpath(ENV["ROOT"])) # Needed for the app
pushfirst!(LOAD_PATH, joinpath(ENV["ROOT"], "packages"))
ENV["JULIA_LOAD_PATH"] = join(LOAD_PATH, ";")

PRECOMPILED = joinpath(ENV["USER_DATA"], "cache", "precompiled")

if !(isdir(joinpath(ENV["ROOT"], "compiled")) || isfile(PRECOMPILED))

    @info "Precompiling..."

    # 3D acceleration needs to be enabled in windows for OpenGL
    if WITH_SPLASH_SCREEN
            
        # include("startup/SplashScreen/SplashScreen.jl")
        # splash_window = SplashScreen.create_splash_window()
        # include("startup/precompile.jl")
        # SplashScreen.close_window(splash_window)

        include("startup/configure.jl")
        touch(PRECOMPILED)

    else
        include("startup/precompile.jl")
    end
end

@info "Precompilation Finished"

redirect_stdout()
redirect_stderr()

end

include(joinpath(ENV["ROOT"], "startup", "init.jl")) # One may set up a logging there
include(joinpath(ENV["ROOT"], ENV["APP_NAME"], "main.jl"))
