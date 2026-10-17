module IconTools

import PNGFiles: save

include("ImageResizing.jl")
include("SVGRenderer.jl")
include("IconForge.jl")

include("ICNS.jl")
include("MSIXIcons.jl")

hello() = 3

import ..IconForge: toicon, totile, load
import ..ICNS: toicns
import ..MSIXIcons: msix_icons

end
