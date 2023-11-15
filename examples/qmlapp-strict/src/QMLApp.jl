module QMLApp

using QML


const _PROPERTIES = JuliaPropertyMap(
    "text" => "Hello World Again!",
    "count" => 16
)


function julia_main()::Cint

    loadqml((@__DIR__) * "/App.qml"; _PROPERTIES)
    exec()

    return 0
end

end # module QMLApp
