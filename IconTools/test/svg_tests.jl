# test/svg_tests.jl — include from runtests.jl, or run standalone.
#
# Exercises the SVG path end-to-end without any external files: SVG sources
# are generated as strings, parsed into SVGImage (header/units/viewBox
# handling), loaded through FileIO (registration), rasterized with imresize
# at exact and non-uniform sizes (checking colour and alpha at known
# positions), and composited onto a canvas that is saved to
# test/output/svg.png.

using Test
using ColorTypes
using FixedPointNumbers: N0f8
using PNGFiles: save
using IconTools.SVGRenderer
using IconTools.SVGRenderer: SVGImage
using IconTools.ImageResizing: imstack!

# left half opaque red, right half untouched (transparent), on a 200×100
# user-unit viewBox
svg_halves(; header = "width=\"200\" height=\"100\"") = """
<?xml version="1.0" encoding="UTF-8"?>
<!-- generated in tests -->
<svg xmlns="http://www.w3.org/2000/svg" $header viewBox="0 0 200 100">
  <rect x="0" y="0" width="100" height="100" fill="#ff0000"/>
</svg>
"""

# a semi-transparent teal disc on a transparent square
svg_disc = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <circle cx="50" cy="50" r="40" fill="#298085" fill-opacity="0.5"/>
</svg>
"""

near(a, b; tol = 2 / 255) = abs(Float64(a) - Float64(b)) <= tol

@testset "SVG" begin

    @testset "header parsing" begin
        s = SVGImage(Vector{UInt8}(codeunits(svg_halves())))
        @test s.width == 200 && s.height == 100
        @test sizeof(s.data) == sizeof(svg_halves())

        # absolute units are converted to px at 96 dpi
        s_mm = SVGImage(Vector{UInt8}(codeunits(svg_halves(header = "width=\"50.8mm\" height=\"1in\""))))
        @test s_mm.width  ≈ 50.8 * 96 / 25.4   # 192 px
        @test s_mm.height ≈ 96.0

        # percentages / missing attributes fall back to the viewBox
        s_pct = SVGImage(Vector{UInt8}(codeunits(svg_halves(header = "width=\"100%\""))))
        @test s_pct.width == 200 && s_pct.height == 100
        s_vb = SVGImage(Vector{UInt8}(codeunits(svg_halves(header = ""))))
        @test s_vb.width == 200 && s_vb.height == 100

        # nothing to size from → clear error
        @test_throws ErrorException SVGImage(Vector{UInt8}(codeunits(
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"1\" height=\"1\"/></svg>")))

        @test occursin("200.0 × 100.0", sprint(show, s))
    end

    @testset "FileIO registration" begin
        mktempdir() do dir
            path = joinpath(dir, "halves.svg")
            write(path, svg_halves())
            s = SVGRenderer.load(path)
            @test s isa SVGImage
            @test (s.width, s.height) == (200, 100)
        end
    end

    @testset "rasterize: exact size and alpha" begin
        s = SVGImage(Vector{UInt8}(codeunits(svg_halves())))
        img = render(s, 50, 100)
        @test img isa Matrix{RGBA{N0f8}}
        @test size(img) == (50, 100)

        # inside the red rect: opaque red
        px = img[25, 25]
        @test near(alpha(px), 1) && near(red(px), 1) && near(green(px), 0) && near(blue(px), 0)
        # right half: fully transparent
        @test near(alpha(img[25, 75]), 0)
        # every row is red-on-the-left, transparent-on-the-right (away from the seam)
        @test all(near(alpha(img[i, 10]), 1) for i in 1:50)
        @test all(near(alpha(img[i, 90]), 0) for i in 1:50)
    end

    @testset "rasterize: partial alpha" begin
        d = SVGImage(Vector{UInt8}(codeunits(svg_disc)))
        img = render(d, 100, 100)
        c = img[50, 50]
        @test near(alpha(c), 0.5; tol = 0.02)
        @test near(red(c), 0x29 / 255; tol = 0.02)
        @test near(green(c), 0x80 / 255; tol = 0.02)
        @test near(blue(c), 0x85 / 255; tol = 0.02)
        @test near(alpha(img[5, 5]), 0)   # corner outside the disc
    end

    @testset "composite onto canvas and save" begin
        cream = RGB{N0f8}(0.96, 0.94, 0.89)
        canvas = fill(cream, 300, 400)

        s = SVGImage(Vector{UInt8}(codeunits(svg_halves())))
        icon = render(s, 100, 200)
        imstack!(canvas, icon, 51, 101)          # occupies rows 51:150, cols 101:300
        # transparent half leaves the canvas untouched; red half overwrites
        @test canvas[100, 250] == cream
        px = canvas[100, 150]
        @test near(red(px), 1) && near(green(px), 0) && near(blue(px), 0)
        # outside the icon
        @test canvas[20, 20] == cream

        d = SVGImage(Vector{UInt8}(codeunits(svg_disc)))
        disc = render(d, 120, 120)
        imstack!(canvas, disc, 161, 241)         # rows 161:280, cols 241:360
        # disc centre: 50% teal over cream
        c = canvas[220, 300]
        @test near(red(c),   0.5 * 0x29 / 255 + 0.5 * 0.96; tol = 0.02)
        @test near(green(c), 0.5 * 0x80 / 255 + 0.5 * 0.94; tol = 0.02)
        @test near(blue(c),  0.5 * 0x85 / 255 + 0.5 * 0.89; tol = 0.02)
        # disc corner (transparent) leaves cream
        @test canvas[165, 245] == cream

        outdir = joinpath(@__DIR__, "output")
        mkpath(outdir)
        outpath = joinpath(outdir, "svg.png")
        save(outpath, canvas)
        @test isfile(outpath) && filesize(outpath) > 0
        @info "Wrote SVG composition" outpath
    end
end
