"""
```julia
product = JuliaImgBundle(source; precompile = true, incremental = false)
snap = Snap(source)
bundle(product, snap, destination)
```

Currently, only `JuliaImgBundle` compilation is supported. In the future, one will be able to specify the product to be `SysImage` (or another better name) to compile the application with `PackageCompiler` instead and perform corresponding bundling. There are also plans to experiment with JuliaC integration.

On the other end, we have the destination in which the product needs to be bundled. Here again, we have a variety to choose from if one were to add Deb, RPM, or Flatpak bundling formats. The `Snap` constructor takes the role of finding configuration files from the user directory and from the default AppBundler recipes folder that one can inspect. Similarly, `MSIX` and `DMG` constructors can be called (see docstrings).

**Custom Product Bundling:** In some situations, you may want to bundle a library which is not supported by the AppBundler product interface, or perhaps bundle other programming language projects like C, Rust, or Python applications. In such situations, you can use:
```julia
dmg = DMG(source)
bundle(dmg, destination) do app_stage
    # Compile project and install it in the appropriate directories of app_stage
end
```

In the future, AppBundler may add support for bundling Python and Rust projects directly.

## Staging

AppBundler offers a staging API for staging products. Currently, only `JuliaImgBundle` staging is supported:

```julia
pkg = JuliaImgBundle(app_dir; precompile = false)
stage(pkg, Linux(:x86_64), "build/linux_staging")
```

This performs the complete staging process for a Julia application, preparing it for distribution on the target platform. The process includes downloading the appropriate Julia runtime, copying application dependencies, retrieving artifacts, configuring startup files, and optionally precompiling the application.

Similar staging API will be made available with PackageCompiler and hopefully also with JuliaC integration.

It is also possible to stage application bundle files:

```julia
msix = MSIX(app_dir)
stage(msix, "build/msix_staging")
```

This is used internally in the `bundle` function and can be useful for debugging purposes.
"""
module AppBundler

using Scratch
import Pkg.BinaryPlatforms: Linux, MacOS, Windows
import Pkg

DOWNLOAD_CACHE = ""

julia_tarballs() = joinpath(DOWNLOAD_CACHE, "julia-tarballs")
artifacts_cache() = joinpath(DOWNLOAD_CACHE, "artifacts")

"""
    BuildSpec

Abstract specification for building and packaging applications.

Concrete subtypes:
- [`JuliaImg.JuliaImgBundle`](@ref): Julia application with full runtime
- [`JuliaC.JuliacBundle`](@ref): Standalone executable compiled with JuliaC
"""
abstract type BuildSpec end

function stage end

include("DMG/DSStore.jl")
include("DMG/HFS.jl")
include("DMG/DMGPack.jl")

include("Snap/SnapPack.jl")

include("MSIX/OpenSSLLegacy.jl")
include("MSIX/MSIXPack.jl")
include("MSIX/MSIXIcons.jl")
include("MSIX/WinSubsystem.jl")

include("bundlers/Resources.jl") # JuliaC needs assets and pkgorigins_index which is shared between JuliaImg and JuliaC
include("bundlers/JuliaImg/JuliaImg.jl") 
include("bundlers/JuliaC.jl")

using .JuliaImg: install
using .JuliaImg.Resources: merge_directories#, install

include("utils.jl")
include("bundle.jl")
include("recipes.jl") 
include("main.jl")

#bundle_app(app_dir, bundle_dir; version = VERSION) = bundle_app(HostPlatform(), app_dir, bundle_dir; version)

function __init__()
    if Sys.iswindows()
        # Prepending with \\?\ for long path support
        global DOWNLOAD_CACHE = "\\\\?\\" * get_scratch!(@__MODULE__, "AppBundler") 
    else
        global DOWNLOAD_CACHE = get_scratch!(@__MODULE__, "AppBundler")
    end

    DSStore.__init__()

end

#import .JuliaImg: JuliaImgBundle

@doc (@doc JuliaImg.JuliaImgBundle) JuliaImgBundle
@doc (@doc JuliaC.JuliaCBundle) JuliaCBundle

export JuliaImgBundle, JuliaCBundle, DMG, MSIX, Snap, bundle, stage
export main 


end
