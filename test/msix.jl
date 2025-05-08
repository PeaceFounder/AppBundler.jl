# ToDo

# try to generate self signed certificate with rcodesign and get the installer to work

# Need to skip the bundling step and go straight to applying a self signed signature

import AppBundler.MSIXPack


source = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/msix-hero-3.1.0.0.msix"
destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/msix-hero-3.1.0.0-repack.msix"

pfx_path = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/JuliaCon2024-AppBundler-Demo/JanisErdmanis.pfx"

#MSIXPack.repack(source, destination; pfx_path, publisher = "CN=JanisErdmanis", password = "YourPassword")

MSIXPack.repack(source, destination)

