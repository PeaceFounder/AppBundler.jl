module QMLApp

using QML
#import AppEnv

global _PROPERTIES::JuliaPropertyMap

function julia_main()::Cint

    #AppEnv.init()

    global _PROPERTIES = JuliaPropertyMap(
        "text" => "Hello World Again!",
        "count" => 16
    )

    loadqml(joinpath(Base.pkgdir(@__MODULE__), "src/App.qml"); _PROPERTIES)
    exec()

    return 0
end

function (@main)(ARGS)
    return julia_main()
end

export main


end # module QMLApp
