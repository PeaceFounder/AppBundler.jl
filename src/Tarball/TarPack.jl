module TarPack

import Tar
import CodecZlib: GzipCompressorStream

# Pack `rootdir` into a gzip-compressed tar at `destination`, with `rootdir`'s
# basename as the archive's single top-level folder (so `tar xzf` extracts into
# `<app>-<version>-<arch>/` instead of spilling bin/, lib/, … into the cwd).
#
# `rootdir` must be the only entry inside its parent (the caller stages into a
# freshly created `<parent>/<name>`), since we tar the parent to capture the
# folder prefix. Tar.create records the owner-execute bit, so the launchers and
# install.sh stay executable; symlinks in the Julia tree are preserved as-is.
#
# The single root is also what makes the archive installable by juliaup, which unpacks a
# distribution with `download_extract_sans_parent(url, dir, 1)` — exactly one leading path
# component is stripped — and then looks for the interpreter at `<root>/bin/julia`.
function pack(rootdir, destination)
    parent = dirname(rootdir)
    name = basename(rootdir)
    entries = readdir(parent)
    entries == [name] ||
        error("TarPack.pack expects $parent to contain only $name, found: $(join(entries, ", "))")

    open(destination, "w") do io
        stream = GzipCompressorStream(io)
        try
            Tar.create(parent, stream)
        finally
            close(stream)
        end
    end

    return
end

end
