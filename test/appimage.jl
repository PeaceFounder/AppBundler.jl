#!/usr/bin/env julia
#
# example.jl -- stage a hello-world AppDir and package it with `AppImage.pack`.
#
# `pack` deliberately does not touch the tree it is given, so building a valid
# AppDir is this script's job: an executable `AppRun` at the root, plus the
# `.desktop` file, icon and `.DirIcon` the format expects.
#
# The exec bit and the root symlinks are set with `chmod`/`symlink`, which
# requires a genuine POSIX filesystem -- fine for a Linux-hosted build, but not
# portable to a Windows host. Packaging cross-platform would stage the same
# tree without those calls and hand the metadata to mksquashfs as a
# pseudo-file instead.
#
#   julia --project example.jl
#
# Set APPIMAGE_ARCH to cross-target another runtime (i686, aarch64, armhf).

using AppBundler.AppImagePack
using Base64

const APP_NAME    = "HelloWorld"
const APP_ID      = "helloworld"          # desktop file / icon basename
const APP_VERSION = "1.0.0"

# ----------------------------------------------------------------- assets --

const APPRUN = """
#!/bin/bash
echo "Hello World"
echo
echo "  APPDIR   = \${APPDIR:-<unset>}"
echo "  APPIMAGE = \${APPIMAGE:-<unset>}"
echo "  OWD      = \${OWD:-<unset>}"
"""

const DESKTOP = """
[Desktop Entry]
Type=Application
Name=$(APP_NAME)
Comment=Minimal AppImage built from Julia
Exec=AppRun
Icon=$(APP_ID)
Categories=Utility;
Terminal=true
X-AppImage-Version=$(APP_VERSION)
"""

# 128x128 PNG, embedded so the script carries no side assets.
const ICON_PNG_BASE64 = replace("""
iVBORw0KGgoAAAANSUhEUgAAAIAAAACABAMAAAAxEHz4AAAAHlBMVEUmMkoFBQV90aUjM0klMkmC26tmp40lMkoAAAAAAACkdcZr
AAAACHRSTlP+AP8Od///ouV+0goAAAMPSURBVHja7ZnPaxNBFMe/O5M0aaJ2Y64KWwterLKh4EGaEvHgRaSnnoQGxJMggv03hN48
iJBePQV66s2TqKBZqL+gtAREvDRmFY0k6e542E2ySTY68ybHzCkb8j68z9uZt5sZIwe9wTBFgEsBJPqfhGHiglSMX48FGKywvC0F
SBUbdWH0wsIiMn9pdVs+8RvvMALAxddK6lvPXBMAwOeD+mUP1Gr38v6n6F0Q5h3V6j+2hxSu7infv1QmkgFXj0d7cwBwlylT6MkA
cPYFBdAu92sgSJMYiVNGkIFVpq2jk0U3yIAfE1ci900wAOeoSzlhAgwQJSqgbQEM4NvkbmICDEKjHdkujJywHDIgcRoMhnZPNOnR
3AUDbDqgbeu3deTyOtHXc5oZaCs40320zQAzwAwwXcCcLkBsaALO18paAGZ7v7UAdx283dABNAAoSIwBkg4A7ycd0OUAsG/RFQ5t
AF6yTAb4eahIxMyDp1CRiFsLX1Qk4gBdFYnY1bhjy0vEAjq78hLx/SCUaNEbSiBRWycDQokPZSpAXmJiT5SVmAgIJRgZgK4DAPsa
bb2u+VyYW9cEbDoAUCADkg0A4Bn5DYgRgVsOAH6pQs0gFKhSayArMElBWmBSBoHA5Sr1NoYCZ9S2gcYEuhXqRAoFyFOZKQjEApYU
BOIA9zwFgRiAmkDMXQi+iAgMb9Bdqf4vgw4ArEQEuGoNdgGejVx7qgDDRqEC6TEO6ORXnuu9aFaymm+q3YomYHSTQRfg0ZrqYBz9
42r2n2kGmAGmBbDBgIcaAAd8Xki+EMaOH7oKFhjxeCkYqToYdAw8gMl0tYlDBHvrdMADaNbAccEA3yYDaiYYsPCNGs+DqWycUAFr
4RnL9xJxFrgIztrSxy0a4U9vNQraeiq56J21tdqE+MSC3+8HGUoKRR/onze+V6/Coz0RATRvHqoKfGymIy3NfKMokSqGRythBnAP
1lRySF1zerMxBKTF19Xbr2Tjt359tsI1aETO3tmiKRffPILb+2kE4JqU2RRpqqZCH9J7sAydjf0FmzPAK8E+tygAAAAASUVORK5CYII=
""", "\n" => "")

# ----------------------------------------------------------------- AppDir --

"""
    build_appdir(root) -> String

Lay out a complete AppDir under `root`, ready to hand to `AppImage.pack`.
"""
function build_appdir(root::AbstractString)
    appdir = joinpath(root, "$(APP_NAME).AppDir")
    rm(appdir; force = true, recursive = true)

    deskdir = joinpath(appdir, "usr", "share", "applications")
    icondir = joinpath(appdir, "usr", "share", "icons", "hicolor", "128x128", "apps")
    mkpath(deskdir)
    mkpath(icondir)

    apprun = joinpath(appdir, "AppRun")
    write(apprun, APPRUN)
    chmod(apprun, 0o755)

    desktop_rel = joinpath("usr", "share", "applications", "$(APP_ID).desktop")
    icon_rel    = joinpath("usr", "share", "icons", "hicolor", "128x128", "apps", "$(APP_ID).png")

    write(joinpath(appdir, desktop_rel), DESKTOP)
    write(joinpath(appdir, icon_rel), base64decode(ICON_PNG_BASE64))

    # Root-level entries the AppImage format expects.
    symlink(desktop_rel, joinpath(appdir, "$(APP_ID).desktop"))
    symlink(icon_rel, joinpath(appdir, "$(APP_ID).png"))
    symlink("$(APP_ID).png", joinpath(appdir, ".DirIcon"))

    return appdir
end

# ------------------------------------------------------------------- main --

"""
    verify(appimage)

Round-trip the result through `AppImage.unpack` and check the entries the
runtime depends on actually survived into the payload.
"""
function verify(appimage::AbstractString)
    mktempdir() do dir
        extracted = unpack(appimage, joinpath(dir, "AppDir"))

        apprun = joinpath(extracted, "AppRun")
        isfile(apprun) || error("AppRun missing from payload")
        (stat(apprun).mode & 0o111) != 0 || error("AppRun is not executable in the payload")

        for entry in (".DirIcon", "$(APP_ID).desktop", "$(APP_ID).png")
            islink(joinpath(extracted, entry)) || error("root entry $entry missing or not a symlink")
        end

        @info "Payload verified" entries = sort(readdir(extracted; join = false))
    end
    return nothing
end

function main(; workdir::AbstractString = joinpath(@__DIR__, "build"),
                arch::AbstractString = get(ENV, "APPIMAGE_ARCH", AppImagePack.host_arch()))
    mkpath(workdir)

    appdir = build_appdir(workdir)
    output = joinpath(@__DIR__, "$(APP_NAME)-$(APP_VERSION)-$(arch).AppImage")

    pack(appdir, output; arch = arch)
    verify(output)

    println()
    println("Try it:")
    println("  ", output)
    println("  APPIMAGE_EXTRACT_AND_RUN=1 ", output, "   # no FUSE (containers, CI)")

    return output
end


main()
