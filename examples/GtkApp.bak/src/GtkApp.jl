module GtkApp

#greet() = print("Hello World!")

using Gtk4

function (@main)(ARGS)

    win = GtkWindow("My First Gtk4.jl Program", 400, 200)

    b = GtkButton("Click Me")
    push!(win,b)

    show(win)

    if !isinteractive()
        c = Condition()
        signal_connect(win, :close_request) do widget
            notify(c)
        end
        @async Gtk4.GLib.glib_main()
        wait(c)
    end
end

export main

end # module GtkApp
