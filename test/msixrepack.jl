# Repack test
import AppBundler.MSIXPack

#source = joinpath(homedir(), "Downloads/Mozilla.Firefox_138.0.4.0_x64__n80bbvh6b1yt2.zip")

#source = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/Mozilla.Firefox_138.0.4.0_x64__n80bbvh6b1yt2"
#destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/MSIX-test/firefox-repack.msix"


source = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/gtkapp2"
destination = "/Volumes/[C] Windows 11/Users/jerdmanis/Documents/gtkapp.msix"


# source = joinpath(homedir(), "Desktop/JuliaCon2024-AppBundler-Demo/PeaceFounderClient/build", "peacefounder-0.1.0-x64-win.msix")
# destination = joinpath(homedir(), "Desktop", "peacefounder-repacked.msix")

#MSIXPack.repack(source, destination)

MSIXPack.pack2msix(source, destination)
