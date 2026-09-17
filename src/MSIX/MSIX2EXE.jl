module MSIX2EXE

using Scratch: @get_scratch!
using p7zip_jll
using Downloads
using SHA

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

#const MSIX_PATH      = joinpath(@__DIR__, "qmlapp.msix")
#const MSIX_PATH      = joinpath(homedir(), "Downloads", "jumbo-26.8.8-x86_64.msix")
#const BOOTSTRAP_PATH = joinpath(@__DIR__, "bootstrap.ps1")
#const OUTPUT_EXE     = joinpath(@__DIR__, "MyAppSetup7z.exe")

# LZMA SDK, from the official ip7z GitHub releases.
const SDK_VERSION = "26.02"
const SDK_FILE    = "lzma2602.7z"
const SDK_URL     = "https://github.com/ip7z/7zip/releases/download/$SDK_VERSION/$SDK_FILE"
const SDK_SHA256  = "2878c85f5f43a4a4e0952b1fd4e5fe097c1c143997a8047c7e1e788892aa9357"

# The installer module. bin/7zS2.sfx and bin/7zS2con.sfx are the "small" SFX
# variants built from C/Util/SfxSetup and do not read this config format.
# Note 7zSD.sfx is a 32-bit GUI PE linked against msvcrt.dll; it runs on x64
# via WoW64 and on ARM64 via x86 emulation.
const SFX_MEMBER = "bin/7zSD.sfx"

# Skip the download by pointing at a stub you already have.
const SFX_LOCAL = ""

sfx_cache() = @get_scratch!("sfx-cache")

#const CACHE_DIR = joinpath(, ".sfx-cache")

# ---------------------------------------------------------------------------
# Installer config
# ---------------------------------------------------------------------------

# const TITLE = "MyApp Installer"

# Written as the logical string; quotes and backslashes are escaped on the way
# out. %%T is left alone -- the module expands it at runtime, so the paths stay
# correct even when the temp directory contains spaces.
#
# The .msix is passed positionally. Drop that second argument only if
# bootstrap.ps1 derives the path itself from $PSScriptRoot.

# const RUN_PROGRAM = string(
#     "powershell.exe -NoProfile -ExecutionPolicy Bypass",
#     " -File \"%%T\\", basename(BOOTSTRAP_PATH), "\"",
#     " \"%%T\\", basename(MSIX_PATH), "\"",
# )

"""
    escape_value(s) -> String

Escape a config value for the SFX text-config parser, which recognises
\\\\, \\", \\n and \\t and passes any other backslash through literally.
"""
escape_value(s::AbstractString) = replace(s, "\\" => "\\\\", "\"" => "\\\"")

"""
    sfx_config(; title, run_program) -> Vector{UInt8}

The installer config block: UTF-8, CRLF, no BOM, between the sentinel lines the
module scans for.
"""
function sfx_config(; title::AbstractString, run_program::AbstractString)
    for (k, v) in ("Title" => title, "RunProgram" => run_program)
        ('\r' in v || '\n' in v) && error("$k may not contain a newline")
    end
    lines = [
        ";!@Install@!UTF-8!",
        "Title=\"$(escape_value(title))\"",
        "Directory=\"\"",                      # see header note -- required
        "RunProgram=\"$(escape_value(run_program))\"",
        ";!@InstallEnd@!",
    ]
    return Vector{UInt8}(codeunits(join(lines, "\r\n") * "\r\n"))
end

# ---------------------------------------------------------------------------
# 7-Zip helpers
# ---------------------------------------------------------------------------

sevenzip(args::Cmd) = p7zip() do exe
    run(pipeline(`$exe $args`, stdout = devnull))
end

sevenzip_out(args::Cmd) = p7zip() do exe
    read(`$exe $args`, String)
end

# ---------------------------------------------------------------------------
# Obtaining the stub
# ---------------------------------------------------------------------------

function fetch_sdk()
    #mkpath(CACHE_DIR)
    #dest = joinpath(CACHE_DIR, SDK_FILE)
    dest = joinpath(sfx_cache(), SDK_FILE)

    if !isfile(dest)
        @info "downloading LZMA SDK" SDK_URL
        Downloads.download(SDK_URL, dest)
    end

    got = bytes2hex(open(sha256, dest))
    if isempty(SDK_SHA256)
        @warn "SDK is not pinned; set SDK_SHA256 before shipping" sha256 = got
    elseif got != lowercase(SDK_SHA256)
        rm(dest; force = true)
        error("""
              SHA256 mismatch for $SDK_FILE
                expected: $(lowercase(SDK_SHA256))
                actual:   $got
              Cached copy deleted. If you bumped SDK_VERSION, update SDK_SHA256.
              """)
    end
    return dest
end

function extract_stub()
    if !isempty(SFX_LOCAL)
        isfile(SFX_LOCAL) || error("SFX_LOCAL does not exist: $SFX_LOCAL")
        @info "using local stub" SFX_LOCAL
        return read(SFX_LOCAL)
    end

    sdk = fetch_sdk()
    dir = mktempdir()

    # `e` flattens, so bin/7zSD.sfx lands as 7zSD.sfx. A filter that matches
    # nothing still exits 0, hence the explicit isfile check below.
    sevenzip(`e -y -o$dir $sdk $SFX_MEMBER`)

    stub = joinpath(dir, basename(SFX_MEMBER))
    if !isfile(stub)
        error("""
              $SFX_MEMBER not found in $SDK_FILE. Archive contents:

              $(sevenzip_out(`l $sdk`))
              """)
    end
    @info "using SFX module" SFX_MEMBER bytes = filesize(stub)
    return read(stub)
end

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

"""
    make_payload(files) -> Vector{UInt8}

Store-only .7z. The MSIX is already a zip, so recompressing costs build time
and gains almost nothing.
"""
function make_payload(files::Vector{String})
    names = basename.(files)
    allunique(names) || error("payload file names collide: $names")

    dir = mktempdir()
    staging = joinpath(dir, "payload")
    mkpath(staging)
    for f in files
        cp(f, joinpath(staging, basename(f)))
    end

    archive = joinpath(dir, "payload.7z")
    sevenzip(`a -mx0 -bso0 -bsp0 $archive $(joinpath(staging, "."))`)
    return read(archive)
end

"""
    verify(exe, expected)

Confirm the appended archive is discoverable and holds exactly what we put in.
7-Zip prefers the trailing 7z over the PE container, so this works on the
finished executable.
"""
function verify(exe::AbstractString, expected::Vector{String})
    out = sevenzip_out(`l $exe`)
    absent = filter(n -> !occursin(n, out), expected)
    isempty(absent) || error("payload not readable back from $exe: $absent\n\n$out")

    m = match(r"Offset = (\d+)", out)
    m === nothing || @info "archive offset" offset = parse(Int, m[1])
    occursin("Method = Copy", out) || @warn "payload is not store-only"
end

function pack(msix, bootstrap, output_exe; title = "MyApp Installer")

    inputs = String[bootstrap, msix]
    for p in inputs
        isfile(p) || error("missing input file: $p")
    end

    run_program = string(
        "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass",
        " -File \"%%T\\", basename(bootstrap), "\"",
        " \"%%T\\", basename(msix), "\"",
    )

    stub    = extract_stub()
    config  = sfx_config(; title, run_program)
    payload = make_payload(inputs)

    open(output_exe, "w") do io
        write(io, stub)
        write(io, config)
        write(io, payload)
    end

    verify(output_exe, basename.(inputs))
    @info "done" output = output_exe bytes = filesize(output_exe)
end

#abspath(PROGRAM_FILE) == (@__FILE__) && main()


end
