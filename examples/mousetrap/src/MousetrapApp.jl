module MousetrapApp

__precompile__(false)

import Mousetrap

function (@main)(ARGS)
    # Execute in Main context to avoid module-related issues
    Base.eval(Main, quote
        using Mousetrap
        Mousetrap.main() do app::Mousetrap.Application
            window = Mousetrap.Window(app)
            Mousetrap.set_child!(window, Mousetrap.Label("Hello World!"))
            Mousetrap.present!(window)
        end
    end)
    return nothing
end

export main

end
