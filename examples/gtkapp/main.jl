using Gtk4

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
