module MakieApp

using GLMakie

function (@main)(ARGS)
    # Create a figure (window)
    fig = Figure(size = (600, 400))
    
    # Add a label with "Hello World"
    Label(fig[1, 1], "Hello World from Makie!", 
          fontsize = 40, 
          color = :blue,
          padding = (50, 50, 50, 50))
    
    # Display the window
    display(fig)
    
    println("Hello World GUI is running. Close the window to exit.")
    
    # Keep the window open
    wait(fig.scene)
end

export main

end # module MakieApp
