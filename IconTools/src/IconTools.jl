module IconTools

import PNGFiles: save
import ColorTypes: RGBA

include("ImageResizing.jl")
include("SVGRenderer.jl")
include("IconForge.jl")

include("ICNS.jl")
include("MSIXIcons.jl")

import ..IconForge: toicon, totile, load
import ..ICNS: toicns
import ..MSIXIcons: tomsix

export RGBA

end
