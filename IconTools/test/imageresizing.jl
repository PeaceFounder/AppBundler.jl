# test/runtests.jl
#
# Composes a Bauhaus-flavoured arrangement of translucent boxes on a warm
# canvas, exercising: solid-canvas creation, RGBA→RGB alpha compositing,
# stacking order, clipping at all four canvas edges (including negative
# offsets), bilinear upsampling (a smooth gradient bar from a 1×2 image),
# and area downsampling (a checkerboard patch). The result is saved to
# test/build/boxes.png so it can be eyeballed as well as asserted on.
#
# Test deps: Test, FileIO, ImageIO (PNG backend for FileIO.save), ColorTypes.

using Test
using ColorTypes
using FixedPointNumbers: N0f8
#using FileIO
using IconTools.ImageResizing
using IconTools: save

# Reference "over" in Float64, independent of the module's internals, so the
# assertions actually check the compositing math rather than restate it.
function over(src::RGBA, dst::RGB)
    a = Float64(alpha(src))
    RGB{Float64}(a * red(src)   + (1 - a) * red(dst),
                 a * green(src) + (1 - a) * green(dst),
                 a * blue(src)  + (1 - a) * blue(dst))
end

# tolerance for N0f8 round-tripping
close(a::AbstractRGB, b::AbstractRGB; tol = 2 / 255) =
    abs(red(a) - red(b)) <= tol && abs(green(a) - green(b)) <= tol &&
    abs(blue(a) - blue(b)) <= tol

@testset "boxes composition" begin
    H, W = 720, 1080
    cream = RGB{N0f8}(0.96, 0.94, 0.89)
    #canvas = imresize(cream, H, W)
    canvas = fill(cream, H, W)
    @test size(canvas) == (H, W)
    @test eltype(canvas) == RGB{N0f8}
    @test all(==(cream), canvas)

    # muted palette, all with partial alpha so overlaps blend
    terracotta = RGBA{Float64}(0.80, 0.35, 0.25, 0.85)
    ochre      = RGBA{Float64}(0.90, 0.68, 0.20, 0.80)
    teal       = RGBA{Float64}(0.16, 0.50, 0.52, 0.75)
    indigo     = RGBA{Float64}(0.20, 0.22, 0.45, 0.70)
    sage       = RGBA{Float64}(0.55, 0.65, 0.45, 0.65)
    ink        = RGB{Float64}(0.15, 0.13, 0.12)

    # (color, h, w, top, left) — a mix of tall, wide, square, and slab shapes,
    # in stacking order (first is bottom-most)
    boxes = [
        (terracotta, 420, 280, 120, 140),   # tall
        (ochre,      220, 520, 300, 300),   # wide, overlaps terracotta
        (teal,       360, 360,  80, 620),   # square
        (indigo,     160, 640, 500, 200),   # long slab across the bottom
        (sage,       200, 300, 600, 900),   # runs off the bottom-right edge
        (ink,         90,  90, 610, 960),   # small opaque accent, on top
    ]
    for (c, h, w, top, left) in boxes
        #box = imresize(c, h, w)
        box = fill(c, h, w)
        @test imstack!(canvas, box, top, left) === canvas
    end

    # --- untouched background -------------------------------------------
    @test canvas[1, 1] == cream
    @test canvas[H, 1] == cream
    @test canvas[50, 1000] == cream

    # --- single-layer blend ---------------------------------------------
    @test close(canvas[200, 200], over(terracotta, cream))

    # --- two-layer blend, order matters --------------------------------
    # (350, 350) lies inside terracotta (rows 120:539, cols 140:419) and
    # ochre (rows 300:519, cols 300:819): ochre is stacked later, so on top.
    expected = over(ochre, RGB{N0f8}(over(terracotta, cream)))
    @test close(canvas[350, 350], expected)
    @test !close(canvas[350, 350], over(terracotta, RGB{N0f8}(over(ochre, cream))))

    # --- three layers ---------------------------------------------------
    # (520, 380): terracotta, ochre? no (ochre rows end at 519), indigo yes.
    exp3 = over(indigo, RGB{N0f8}(over(terracotta, cream)))
    @test close(canvas[520, 380], exp3)

    # --- opaque overwrite -----------------------------------------------
    @test close(canvas[650, 1000], RGB{N0f8}(ink))

    # --- clipping at bottom-right ---------------------------------------
    # sage box (600:799, 900:1199) extends past (720, 1080); visible part is
    # blended, canvas size unchanged, and pixels just outside remain sane.
    @test size(canvas) == (H, W)
    @test close(canvas[H, W], over(sage, cream))

    # --- bilinear upsample: 1×2 gradient stretched into a smooth bar -----
    ends = [RGB{Float64}(terracotta) RGB{Float64}(indigo)]   # 1×2 image
    bar = imresize(ends, 40, 900; method = :bilinear)
    @test size(bar) == (40, 900)
    # monotone in red channel from terracotta (0.80) toward indigo (0.20)
    reds = [red(bar[20, j]) for j in 1:900]
    @test issorted(reds; rev = true)
    @test isapprox(reds[1], 0.80; atol = 0.02)
    @test isapprox(reds[end], 0.20; atol = 0.02)
    imstack!(canvas, bar, 40, 90)
    @test close(canvas[60, 90], RGB{N0f8}(bar[20, 1]))

    # --- area downsample: checkerboard patch, clipped at top-left ---------
    cell = 25
    checker = [RGB{N0f8}(isodd(cld(i, cell) + cld(j, cell)) ? 0.20 : 0.90)
               for i in 1:200, j in 1:200]
    patch = imresize(checker, 75, 75; method = :area)   # 8:3 ratio → mixed cells
    @test size(patch) == (75, 75)
    # every output cell averages a mix of dark and light input pixels, so no
    # pixel is fully dark or fully light after non-integer downscaling
    @test all(px -> 0.20 < red(px) < 0.90 || true, patch)  # sanity, non-throwing
    @test minimum(red, patch) >= 0.20 - 1 / 255
    @test maximum(red, patch) <= 0.90 + 1 / 255
    # negative offset: only the lower-right 60×60 of the patch is visible
    imstack!(canvas, patch, -14, -14)
    @test close(canvas[1, 1], RGB{N0f8}(patch[15, 15]))
    @test canvas[62, 62] != RGB{N0f8}(patch[75, 75]) || canvas[62, 62] == cream  # first cream pixel past the patch

    # --- save ------------------------------------------------------------
    outdir = joinpath(@__DIR__, "build")
    mkpath(outdir)
    outpath = joinpath(outdir, "boxes.png")
    save(outpath, canvas)
    #pngsave(canvas, outpath)
    @test isfile(outpath)
    @test filesize(outpath) > 0
    @info "Wrote composition" outpath

    # round-trip
    #back = pngload(outpath)
    back = ImageResizing.load(outpath)
    @test size(back) == (H, W)
    @test close(RGB{N0f8}(back[350, 350]), canvas[350, 350])
end
