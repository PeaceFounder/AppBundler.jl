module IconTools

include("ImageResizing.jl")
include("SVGRenderer.jl")

include("Rendering.jl")

import ..Rendering: toicon, totile, load

end
