# MSIX

MSIX is the modern Windows application package format. AppBundler builds `.msix` packages with a fully open-source toolchain, so packages can be created on any platform without the Windows SDK.

![MSIX installation](msix-installation.gif)

## Build pipeline

The standard Microsoft workflow packs a staging directory with `MakeAppx` and signs it with `SignTool`. Because these Windows SDK tools cannot be redistributed, AppBundler uses open-source equivalents:

```
StagingDir → msixpack → osslsigncode → MyApp.msix
```

Both tools are cross-compiled with [BinaryBuilder](https://github.com/JuliaPackaging/BinaryBuilder.jl), which makes it possible to build and sign MSIX packages from Linux and macOS as well as Windows.

## Package contents

Before packing, AppBundler assembles `StagingDir/` with the following layout:

| Path | Purpose |
|------|---------|
| `AppxManifest.xml` | Package identity, entry point, and capabilities |
| `resources.pri` | Resource index; required for icons to render correctly |
| `Assets/` | Application icons |
| `Msix.AppInstaller.Data/MSIXAppInstallerData.xml` | App Installer configuration |
| `MyApp.exe` | Application launcher |

Sandboxing and permissions are set through the capabilities in `AppxManifest.xml`. The target system must have the Universal C Runtime (UCRT).

!!! warning "GUI subsystem and console processes"
    AppBundler switches `MyApp.exe` to the Windows GUI subsystem so that no console window appears on launch. For GUI applications this currently leaves a zombie console process behind. This is a known limitation.

## Code signing

For a user-friendly installation, the MSIX must be signed with a certificate chaining to a trusted root. Options as of September 2026 include:

- Microsoft Store signing (free, subject to review)
- Azure Artifact Signing (€10/month)
- Certum Open Source Code Signing (€25/year)

Within an organisation, administrators may also deploy an internal trusted root to company machines and sign applications with it.

AppBundler currently expects a password-protected `.pfx` file, while many providers deliver keys on hardware tokens or through cloud signing services. Hardware token support is planned. Until then, build with `--skipsign` and sign separately, or use the lower-level signing API described in [reference.md](reference.md).

The publisher in `AppxManifest.xml` must exactly match the certificate subject, including order, spaces, and commas. Set it in `LocalPreferences.toml`:

```toml
msix_publisher = "CN=AppBundler, C=XX, O=PeaceFounder"
```

### Self-signing

For testing, AppBundler can generate a self-signed certificate at `msix/certificate.pfx`:

```julia
AppBundler.install_msix_certificate("msix/certificate.pfx")
```

The generated password is printed to stdout. Pass it to the build with `--password=mypassword`. For a quick local build, use `--selfsign` instead: it signs with a throwaway certificate and ignores `msix/certificate.pfx`.

Either way, the package is trusted only on machines where its certificate has been installed, as described below.

## Installing self-signed packages

A self-signed package installs only after its certificate is added to the trusted root authorities, which can be done manually from the package properties ([guide](https://www.advancedinstaller.com/install-test-certificate-from-msix.html)). To automate this, AppBundler provides `recipes/msix/bootstrap.ps1`, which extracts the certificate, trusts it, and launches the installer:

```powershell
bootstrap.ps1 myapp.msix           # graphical installer
bootstrap.ps1 myapp.msix -Console  # console installation
```

This also enables one-line web installs: a hosted `install.ps1` can download the MSIX and `bootstrap.ps1` and run `bootstrap.ps1 myapp.msix -Console`, invoked with e.g.:

```powershell
irm https://example.com/install.ps1 | iex
```

## Installer EXE

AppBundler can wrap the MSIX in a 7-Zip self-extracting executable. On launch it extracts the package and `bootstrap.ps1` to a temporary directory and runs `bootstrap.ps1 myapp.msix`.

Enable it with `-Dmsix2exe=true` or persistently with `msix2exe = true` in `LocalPreferences.toml`. Set `msix2exe_windowed = true` to launch the graphical installer after extraction.

## API

```julia
msix_config = MSIX(project; selfsign = true)

bundle(msix_config, msix_archive) do app_stage
    # install files into app_stage
end

msix2exe_config = MSIX2EXE(project)
repack(msix_archive, msix2exe_config, exe_archive)
```

```@docs
AppBundler.MSIX
AppBundler.MSIX2EXE
```
