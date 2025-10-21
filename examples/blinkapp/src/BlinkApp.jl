module BlinkApp

using Blink

function (@main)(ARGS)

    w = Window(; async=false) # Open a new window
    body!(w, "Hello World") 
    wait(w.shell.proc)

    return
end

export main

end # module BlinkApp
