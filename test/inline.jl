using Test
using AppBundler
import AppBundler: inline, main_inline, DEFAULT_DIR, BINARY_TARGETS, TEMPLATE_TARGETS, GENERATED_TARGETS

const EXAMPLE_DIR = joinpath(pkgdir(AppBundler), "examples", "GLApp")

# Copy of the example project without its `meta/` overrides, so every target starts out absent
function fresh_project()
    project = joinpath(mktempdir(), "GLApp")
    cp(EXAMPLE_DIR, project)
    rm(joinpath(project, "meta"); recursive = true, force = true)
    return project
end

recipe(path) = joinpath(DEFAULT_DIR, path)

const MUSTACHE_TAG = r"\{\{[^}]*\}\}"


@testset "Binary artifact inlining" begin

    @testset "$target" for (target, source) in BINARY_TARGETS
        project = fresh_project()
        #destination = inline(project, target; render = false)
        inline(project, target; render = false)
        
        destination = joinpath(project, target)

        @test read(destination) == read(recipe(source))
    end

    @testset "Existing destination requires force" begin
        project = fresh_project()
        inline(project, "meta/icon.png"; render = false)
        destination = joinpath(project, "meta/icon.png")

        write(destination, "customised")

        @test_throws ErrorException inline(project, "meta/icon.png"; render = false)
        @test read(destination, String) == "customised"

        inline(project, "meta/icon.png"; render = false, force = true)
        @test read(destination) == read(recipe(BINARY_TARGETS["meta/icon.png"]))
    end
end


@testset "Template rendering" begin

    @testset "Raw copy: $target" for (target, source) in TEMPLATE_TARGETS
        project = fresh_project()
        inline(project, target; render = false)
        destination = joinpath(project, target)
        @test read(destination, String) == read(recipe(source), String)
    end

    # # CI workflows are skipped: GitHub Actions' own `${{ ... }}` syntax is not Mustache
    meta_templates = sort!([target for target in keys(TEMPLATE_TARGETS) if startswith(target, "meta/")])

    @testset "Rendered: $target" for target in meta_templates
        project = fresh_project()
        main_inline(project, target, String["--render"])
        destination = joinpath(project, target)
        content = read(destination, String)
        raw = read(recipe(TEMPLATE_TARGETS[target]), String)

        @test !occursin(MUSTACHE_TAG, content)
        if occursin(MUSTACHE_TAG, raw)
            @test content != raw
        end
    end

    @testset "Rendering picks up command-line preferences" begin
        project = fresh_project()
        main_inline(project, "meta/msix/AppxManifest.xml", ["--render", "-Dmsix.publisher=CN=TestPublisher"])
        destination = joinpath(project, "meta/msix/AppxManifest.xml")
        @test occursin("CN=TestPublisher", read(destination, String))
    end

    @testset "Existing rendered template requires force" begin
        project = fresh_project()
        main_inline(project, "meta/dmg/Info.plist", String["--render"])
        destination = joinpath(project, "meta/dmg/Info.plist")
        write(destination, "customised")

        @test_throws ErrorException main_inline(project, "meta/dmg/Info.plist", String["--render"])
        @test read(destination, String) == "customised"

        main_inline(project, "meta/dmg/Info.plist", String["--render", "--force", "--verbose"])
        @test !occursin(MUSTACHE_TAG, read(destination, String))
    end
end


const PNG_MAGIC = UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]

be32(bytes, i) = ntoh(only(reinterpret(UInt32, bytes[i:i+3])))

ispng(path) = isfile(path) && read(path, 8) == PNG_MAGIC

# # Width and height from the PNG IHDR chunk
function png_size(path)
    bytes = read(path)
    @assert bytes[1:8] == PNG_MAGIC && String(bytes[13:16]) == "IHDR"
    return (be32(bytes, 17), be32(bytes, 21))
end

@testset "Generated targets" begin

    @testset "meta/msix/Assets" begin
        project = fresh_project()
        main_inline(project, "meta/msix/Assets", String[])
        destination = joinpath(project, "meta/msix/Assets")

        @test isdir(destination)
        files = readdir(destination; join = true)
        @test !isempty(files)
        @test all(ispng, files)

        @testset "Regenerating with force replaces stale files" begin
            stale = joinpath(destination, "stale.png")
            write(stale, "stale")
            @test_throws ErrorException main_inline(project, "meta/msix/Assets", String[])
            @test isfile(stale)

            main_inline(project, "meta/msix/Assets", String["--force"])
            @test !ispath(stale)
            @test all(ispng, readdir(destination; join = true))
        end
    end

    @testset "meta/dmg/icon.icns" begin
        project = fresh_project()
        main_inline(project, "meta/dmg/icon.icns", String[])
        destination = joinpath(project, "meta/dmg/icon.icns")

        bytes = read(destination)
        @test String(bytes[1:4]) == "icns"
        @test be32(bytes, 5) == length(bytes)
    end

    @testset "meta/snap/icon.png" begin
        project = fresh_project()
        main_inline(project, "meta/snap/icon.png", String[])
        destination = joinpath(project, "meta/snap/icon.png")
        @test ispng(destination)
        @test png_size(destination) == (512, 512)
    end

    @testset "meta/dmg/DS_Store" begin
        project = fresh_project()
        main_inline(project, "meta/dmg/DS_Store", String[])
        destination = joinpath(project, "meta/dmg/DS_Store")

        bytes = read(destination)
        @test length(bytes) > 8
        @test be32(bytes, 1) == 1
        @test String(bytes[5:8]) == "Bud1"
    end

    @testset "$target" for target in ("meta/msix/certificate.pfx", "meta/dmg/certificate.pfx")
        project = fresh_project()
        main_inline(project, target, String[])
        destination = joinpath(project, target)

        bytes = read(destination)
        @test !isempty(bytes)
        @test first(bytes) == 0x30   # DER-encoded PKCS#12 starts with a SEQUENCE

        @test_throws ErrorException main_inline(project, target, String[])
        main_inline(project, target, String["--force"])
        @test read(destination) != bytes   # a fresh key pair, not the old file
    end
end
