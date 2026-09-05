import AppBundler
import AppBundler: AppImage, bundle, stage, AppImagePack

using Test

const APP = joinpath(pkgdir(AppBundler), "examples", "GtkApp")

"""
Stand-in for the AppImage runtime. Using a stub keeps these tests free of the network and of
`AppImageRuntime_jll`.

It has to be a *plausible* 64 bit ELF rather than a blank buffer, because `offset` derives the
payload position from the section header table exactly as the real runtime does. A stub of zeros
would let a wrong implementation pass.
"""
function stub_runtime(path = tempname(); size = 4096)

    bytes = zeros(UInt8, size)
    bytes[1:4] = UInt8[0x7f, 0x45, 0x4c, 0x46]  # \x7fELF
    bytes[5] = 0x02                             # 64 bit
    bytes[9:11] = UInt8[0x41, 0x49, 0x02]       # AI\x02

    # Section headers placed so that e_shoff + e_shentsize * e_shnum == size, which is what an ELF
    # whose payload starts immediately afterwards looks like.
    shentsize, shnum = 64, 1
    shoff = size - shentsize * shnum

    bytes[41:48] = reinterpret(UInt8, [UInt64(shoff)])
    bytes[59:60] = reinterpret(UInt8, [UInt16(shentsize)])
    bytes[61:62] = reinterpret(UInt8, [UInt16(shnum)])

    # The real runtime embeds squashfuse, whose own "hsqs" constant sits some 750 KB before the
    # actual payload. Reproducing that here keeps `offset` honest: locating the payload by
    # scanning for the squashfs magic finds this instead and reports a position inside the runtime.
    bytes[1025:1028] = UInt8[0x68, 0x73, 0x71, 0x73]

    write(path, bytes)

    return path
end

function fake_payload(root)
    mkpath(joinpath(root, "bin"))
    write(joinpath(root, "bin", "julia"), "#!/bin/sh\necho fake julia\n")
    Sys.isunix() && chmod(joinpath(root, "bin", "julia"), 0o755)
    return root
end

@testset "AppImage configuration" begin

    appimage = AppImage(APP; arch = :x86_64)

    @test appimage.arch == :x86_64
    @test appimage.compress
    @test appimage.compression == :zstd
    @test appimage.depot == "app"

    @test AppBundler.suffix(appimage) == ".AppImage"

    # AppImages are conventionally named <App>-<version>-<arch>.AppImage
    @test AppBundler.canonical_target_name(appimage) ==
        "$(appimage.parameters["APP_NAME"])-$(appimage.parameters["APP_VERSION"])-x86_64"

    @test AppBundler.suffix(AppImage(APP; compress = false)) == ""

    # A compressor mksquashfs does not have must be rejected before it is invoked, and the
    # runtime only links squashfuse with zstd and zlib.
    @test_throws ErrorException AppImage(APP; compression = :bzip2)
    @test_throws ErrorException AppImage(APP; depot = "elsewhere")
end

@testset "AppDir staging" begin

    destination = mktempdir()
    appimage = AppImage(APP; arch = :x86_64)
    stage(appimage, destination)

    app_name = appimage.parameters["APP_NAME"]

    # AppRun is the entry point the runtime executes after mounting
    apprun = joinpath(destination, "AppRun")
    @test isfile(apprun)
    Sys.isunix() && @test (stat(apprun).mode & 0o111) != 0

    # The spec requires the desktop entry and the icon at the AppDir root
    @test isfile(joinpath(destination, "$app_name.desktop"))
    @test isfile(joinpath(destination, "$app_name.png"))

    # `.DirIcon` is what file managers read for the thumbnail
    dir_icon = joinpath(destination, ".DirIcon")
    @test ispath(dir_icon)
    @test read(dir_icon) == read(joinpath(destination, "$app_name.png"))

    # Icon= names the icon without a path or extension, otherwise desktop integration silently
    # falls back to a generic icon
    desktop = read(joinpath(destination, "$app_name.desktop"), String)
    @test occursin("Icon=$app_name\n", desktop)
    @test !occursin("Icon=$app_name.png", desktop)
    @test occursin("Type=Application", desktop)

    # Freedesktop copies, so an installed AppImage integrates with the menu
    @test isfile(joinpath(destination, "usr/share/applications/$app_name.desktop"))
    @test isfile(joinpath(destination, "usr/share/icons/hicolor/256x256/apps/$app_name.png"))

    bundle_id = appimage.parameters["BUNDLE_IDENTIFIER"]
    @test isfile(joinpath(destination, "usr/share/metainfo/$bundle_id.appdata.xml"))
end

@testset "Packing an AppImage" begin

    appdir = mktempdir()
    stage(AppImage(APP; arch = :x86_64), appdir)
    fake_payload(appdir)

    runtime = stub_runtime()
    destination = joinpath(mktempdir(), "Demo-x86_64.AppImage")

    AppImagePack.pack(appdir, destination, runtime; compression = :zstd)

    @test isfile(destination)

    # An AppImage is the runtime followed by the squashfs, so the file must begin with the
    # runtime byte for byte and carry the magic at offset 8.
    prefix = read(runtime)
    @test read(destination)[1:length(prefix)] == prefix
    @test read(destination)[9:11] == UInt8[0x41, 0x49, 0x02]

    # The payload starts exactly where the runtime ends; this is what `--appimage-offset` reports.
    # The stub embeds a decoy "hsqs" the way the real runtime does, so a scan-based
    # implementation would report a position inside the runtime instead.
    @test AppImagePack.offset(destination) == filesize(runtime)
    @test AppImagePack.offset(destination) > 1028
    @test filesize(destination) > filesize(runtime)

    Sys.isunix() && @test (stat(destination).mode & 0o111) != 0

    # Reading the payload back without FUSE is the escape hatch for a site that cannot mount
    extracted = mktempdir()
    AppImagePack.unpack(destination, extracted)

    @test isfile(joinpath(extracted, "AppRun"))
    @test isfile(joinpath(extracted, "bin", "julia"))
end

@testset "Runtime resolution" begin

    runtime = stub_runtime()

    # An explicit path wins over everything else
    @test AppBundler.AppImageRuntime.resolve(:x86_64; runtime) == runtime

    @test_throws ErrorException AppBundler.AppImageRuntime.resolve(:x86_64;
                                                                  runtime = "/no/such/runtime")

    # With nothing available the error has to name both remedies, since this is the one step
    # that fails for a reason outside the user's own project.
    message = try
        AppBundler.AppImageRuntime.resolve(:x86_64; runtime = nothing, allow_jll = false)
        ""
    catch err
        sprint(showerror, err)
    end

    @test occursin("AppImageRuntime_jll", message)
    @test occursin("appimage_runtime", message)
end

@testset "AppImage bundle round trip" begin

    appimage = AppImage(APP; arch = :x86_64, runtime = stub_runtime())
    destination = joinpath(mktempdir(), "$(AppBundler.canonical_target_name(appimage)).AppImage")

    bundle(appimage, destination) do appdir
        fake_payload(appdir)
    end

    @test isfile(destination)
    @test AppImagePack.offset(destination) == filesize(appimage.runtime)

    extracted = mktempdir()
    AppImagePack.unpack(destination, extracted)
    @test isfile(joinpath(extracted, "bin", "julia"))
    @test isfile(joinpath(extracted, "AppRun"))

    # Refuses to clobber unless asked
    @test_throws ErrorException bundle(identity, appimage, destination)
    bundle(identity, appimage, destination; force = true)
    @test isfile(destination)
end

@testset "AppRun depot selection" begin

    app_scoped = mktempdir()
    stage(AppImage(APP; arch = :x86_64, depot = "app"), app_scoped)
    apprun = read(joinpath(app_scoped, "AppRun"), String)

    # Default: a persistent per-user depot that never touches the host ~/.julia
    @test occursin("USER_DATA", apprun)
    @test occursin("XDG_DATA_HOME", apprun)
    @test !occursin(".julia", apprun)

    stock = mktempdir()
    appimage = AppImage(APP; arch = :x86_64, depot = "julia")
    stage(appimage, stock)
    apprun = read(joinpath(stock, "AppRun"), String)

    # `julia` mode leaves the depot alone so HPC users keep their existing environments
    @test !occursin("USER_DATA=", apprun)

    # That mode swaps in a startup file which sets up the load path without replacing
    # DEPOT_PATH. It is only ever executed on the target machine, so at least confirm here that
    # it renders to parseable Julia and calls the AppEnv entry points it relies on.
    @test !isnothing(appimage.startup_file)

    rendered = joinpath(mktempdir(), "startup.jl")
    AppBundler.install(appimage.startup_file, rendered; parameters = appimage.parameters)
    source = read(rendered, String)

    @test Meta.parse("begin\n" * source * "\nend") isa Expr
    @test occursin("set_load_path!", source)
    @test occursin("load_config", source)

    # AppEnv.init() would replace DEPOT_PATH, which is exactly what this mode avoids. Comments
    # are stripped first, since the file explains that reasoning in prose.
    code = join((first(split(line, '#')) for line in split(source, '\n')), "\n")
    @test !occursin("AppEnv.init()", code)

    # The startup file calls these directly, so a rename upstream should fail here rather than on
    # a user's machine at launch.
    import AppEnv
    for name in [:load_config, :set_load_path!, :load_pkgorigins!]
        @test isdefined(AppEnv, name)
    end
end
