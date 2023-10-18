JULIA = ENV["JULIA"]

SPLASH_SCREEN = joinpath(@__DIR__, "SplashScreen", "SplashScreen.jl")

process = run(`$JULIA --startup-file=no --compiled-modules=no --compile=min -L $SPLASH_SCREEN --eval "SplashScreen.create_splash_window(); sleep(900)"`, wait=false)

include("precompile.jl") 

kill(process)

# It would be much nicer if the splash screen could be displayed from the same process from which 
# the precompilation happens. Unfortunatelly, loading GLAbstraction takes too much time thus it
# needs to be sped up by disabling compilation of the modules. A possible strategy forward seems
# to write the splash screen in ModernGL which does load quick. Feasability of that is something
# which can be investigated further.

# include("SplashScreen/SplashScreen.jl")
# splash_window = SplashScreen.create_splash_window()
# SplashScreen.close_window(splash_window)
