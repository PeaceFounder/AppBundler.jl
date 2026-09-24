using AppBundler

build_dir = joinpath(dirname(@__DIR__), "build")
mkpath(build_dir)

msix = MSIX(joinpath(@__DIR__, "../examples/GtkApp"); selfsign=true, predicate = "juliaimg", windowed = false)
#msix = MSIX(joinpath(@__DIR__, "../examples/GtkApp"); selfsign=true, predicate = "juliaimg", windowed = false)

dest = joinpath(build_dir, "myapp.msix")
rm(dest; force=true)
bundle(msix, dest) do app_stage
    @info "The MSIX app stage is $app_stage"
    touch(joinpath(app_stage, "MRF_signal.mrd"))
end

msix2exe = AppBundler.MSIX2EXE(joinpath(@__DIR__, "../examples/GtkApp"))
AppBundler.repack(dest, msix2exe, joinpath(build_dir, "myapp.exe"))
