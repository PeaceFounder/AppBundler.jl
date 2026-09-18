param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Msix
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------

# Set this to your known thumbprint to refuse anything else. Without it, this
# script trusts whatever certificate the package happens to carry.
$ExpectedThumbprint = ""

# ======================================================================
# Functions
# ======================================================================

# ----------------------------------------------------------------------
# Get-MsixInfo: read the signing certificate out of the package directly
# ----------------------------------------------------------------------
#
# Get-AuthenticodeSignature is avoided on the fast path because it does two
# expensive things we do not need here:
#
#   1. Builds and validates the full certificate chain, including revocation
#      lookups. For a self-signed certificate the CDP is absent or unreachable,
#      so this waits out a network timeout.
#   2. Hashes the entire package through the Appx SIP. That cost scales with
#      package size, and the .msix was just written to %TEMP% by the SFX.
#
# Neither buys anything: the certificate is not trusted yet, so validation
# cannot succeed at this point anyway. The signature IS still verified at
# install time by App Installer, once the certificate is in TrustedPeople.
#
# An MSIX is an OPC zip, so AppxSignature.p7x can be read directly -- a few
# kilobytes instead of the whole package.

# AppxSignature.p7x is a PKCS#7 blob behind a short fixed header. Rather than
# assume the header length, find the offset at which a DER SEQUENCE's declared
# length accounts for exactly the remaining bytes.
function Get-DerOffset {
    param(
        [byte[]]$Bytes,
        [int]$MaxScan = 64
    )

    $n = $Bytes.Length
    $limit = [Math]::Min($MaxScan, $n - 2)

    for ($i = 0; $i -lt $limit; $i++) {

        if ($Bytes[$i] -ne 0x30) { continue }        # SEQUENCE

        $l1 = $Bytes[$i + 1]

        if     ($l1 -lt 0x80) { $hdr = 2; $len = [int]$l1 }
        elseif ($l1 -eq 0x81) { $hdr = 3; $len = [int]$Bytes[$i + 2] }
        elseif ($l1 -eq 0x82) { $hdr = 4; $len = ([int]$Bytes[$i + 2] -shl 8) -bor $Bytes[$i + 3] }
        elseif ($l1 -eq 0x83) { $hdr = 5; $len = ([int]$Bytes[$i + 2] -shl 16) -bor ([int]$Bytes[$i + 3] -shl 8) -bor $Bytes[$i + 4] }
        elseif ($l1 -eq 0x84) { $hdr = 6; $len = ([int]$Bytes[$i + 2] -shl 24) -bor ([int]$Bytes[$i + 3] -shl 16) -bor ([int]$Bytes[$i + 4] -shl 8) -bor $Bytes[$i + 5] }
        else { continue }

        if (($i + $hdr + $len) -eq $n) { return $i }
    }

    return -1
}

# Returns the signer certificate and the package identity name in one pass over
# the zip. The identity name is used later to confirm the install actually
# completed.
function Get-MsixInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.Security

    $signatureBytes = $null
    $manifestXml = $null

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry("AppxSignature.p7x")
        if (-not $entry) {
            throw "AppxSignature.p7x not found; the package is unsigned."
        }

        $ms = New-Object System.IO.MemoryStream
        $stream = $entry.Open()
        try { $stream.CopyTo($ms) } finally { $stream.Dispose() }
        $signatureBytes = $ms.ToArray()

        # Best effort; the install works without it.
        $manifestEntry = $zip.GetEntry("AppxManifest.xml")
        if ($manifestEntry) {
            $stream = $manifestEntry.Open()
            try {
                $reader = New-Object System.IO.StreamReader($stream)
                try { $manifestXml = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
        }
    }
    finally {
        $zip.Dispose()
    }

    $offset = Get-DerOffset -Bytes $signatureBytes
    if ($offset -lt 0) {
        throw "Could not locate a PKCS#7 structure in AppxSignature.p7x."
    }
    if ($offset -gt 0) {
        $signatureBytes = $signatureBytes[$offset..($signatureBytes.Length - 1)]
    }

    # Decode parses without verifying, which is what we want here.
    $cms = New-Object System.Security.Cryptography.Pkcs.SignedCms
    $cms.Decode($signatureBytes)

    $cert = $null
    if ($cms.SignerInfos.Count -gt 0) { $cert = $cms.SignerInfos[0].Certificate }
    if (-not $cert -and $cms.Certificates.Count -gt 0) { $cert = $cms.Certificates[0] }
    if (-not $cert) {
        throw "No signer certificate present in AppxSignature.p7x."
    }

    $identityName = $null
    if ($manifestXml) {
        try { $identityName = $manifestXml.Package.Identity.Name } catch { }
    }

    return [pscustomobject]@{
        Certificate  = $cert
        IdentityName = $identityName
    }
}

# ----------------------------------------------------------------------
# Install-TrustedCertificate: trust the signer, elevating only if needed
# ----------------------------------------------------------------------
#
# Reading LocalMachine\TrustedPeople needs no elevation; only adding to it
# does. So check first, unelevated, and only raise a UAC prompt when the
# certificate is actually missing.

# Ensures the certificate is in LocalMachine\TrustedPeople and returns the
# store copy. Elevates only if the certificate is not already there.
function Install-TrustedCertificate {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $thumbprint = $Certificate.Thumbprint
    $storeEntry = "Cert:\LocalMachine\TrustedPeople\$thumbprint"

    if (Test-Path -LiteralPath $storeEntry) {
        Write-Host "Certificate is already trusted; no elevation needed."
        return Get-Item -LiteralPath $storeEntry
    }

    $certPath = Join-Path $env:TEMP "AppBundler-$thumbprint.cer"

    # The certificate may come from the CMS rather than from a store, so write
    # the DER bytes directly instead of using Export-Certificate.
    [System.IO.File]::WriteAllBytes($certPath, $Certificate.Export("Cert"))

    Write-Host "Installing certificate into LocalMachine\TrustedPeople (requires elevation)..."

    try {
        # A single pre-quoted argument string: Windows PowerShell 5.1 does not
        # quote array elements passed to -ArgumentList, which breaks on paths
        # containing spaces.
        $process = Start-Process `
            -FilePath "certutil.exe" `
            -Verb RunAs `
            -WindowStyle Hidden `
            -ArgumentList "-f -addstore TrustedPeople `"$certPath`"" `
            -Wait `
            -PassThru
    }
    catch {
        throw "Certificate installation was cancelled or could not be elevated: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $certPath -Force -ErrorAction SilentlyContinue
    }

    # Verify unelevated, the same way we checked.
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $storeEntry)) {
        throw "Failed to install the certificate (certutil exit code $($process.ExitCode))."
    }

    Write-Host "Certificate installed and verified."
    return Get-Item -LiteralPath $storeEntry
}

# ======================================================================
# Main
# ======================================================================

# ----------------------------------------------------------------------
# Resolve MSIX path
# ----------------------------------------------------------------------

$Msix = (Resolve-Path -LiteralPath $Msix).Path

Write-Host "Installing: $Msix"

# ----------------------------------------------------------------------
# Read the signing certificate
# ----------------------------------------------------------------------

$stopwatch = [Diagnostics.Stopwatch]::StartNew()

$identityName = $null

try {
    $info = Get-MsixInfo -Path $Msix
    $cert = $info.Certificate
    $identityName = $info.IdentityName
}
catch {
    Write-Host "Fast certificate read failed: $($_.Exception.Message)"
    Write-Host "Falling back to Get-AuthenticodeSignature (this may take a while)..."

    $sig = Get-AuthenticodeSignature -LiteralPath $Msix

    if (-not $sig.SignerCertificate) {
        throw "The MSIX package does not contain a signing certificate."
    }

    # Uncomment to reject packages whose signature isn't valid. Note this can
    # only ever pass on the fallback path, and only once the certificate is
    # already trusted -- so on a first install it will always fail.
    #
    # if ($sig.Status -ne "Valid") {
    #     throw "MSIX signature is not valid: $($sig.Status)"
    # }

    $cert = $sig.SignerCertificate
}

$stopwatch.Stop()

$thumbprint = $cert.Thumbprint

Write-Host "Signer: $($cert.Subject)"
Write-Host "Thumbprint: $thumbprint"
Write-Host ("Certificate read in {0:N0} ms" -f $stopwatch.Elapsed.TotalMilliseconds)

if ($identityName) {
    Write-Host "Package identity: $identityName"
}

if ($ExpectedThumbprint -and $thumbprint -ne $ExpectedThumbprint) {
    throw "Unexpected signer thumbprint: $thumbprint (expected $ExpectedThumbprint)"
}

# ----------------------------------------------------------------------
# Ensure the signing certificate is trusted
# ----------------------------------------------------------------------

Write-Host ""
$installed = Install-TrustedCertificate -Certificate $cert
Write-Host "Valid from: $($installed.NotBefore)"
Write-Host "Valid to:   $($installed.NotAfter)"

# ----------------------------------------------------------------------
# Hand off to App Installer
# ----------------------------------------------------------------------

# Note which App Installer instances are already running, so that if one is
# open from an earlier install we wait on the new one rather than that.
$existingIds = @(
    Get-Process -Name 'AppInstaller' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Id
)

Write-Host ""
Write-Host "Launching App Installer..."

Start-Process $Msix

# The SFX deletes the temp folder as soon as this script exits, so hold on
# until App Installer has finished with the .msix.

$appearTimeout = 120
$deadline = (Get-Date).AddSeconds($appearTimeout)
$proc = $null

while (-not $proc -and (Get-Date) -lt $deadline) {

    $proc = Get-Process -Name 'AppInstaller' -ErrorAction SilentlyContinue |
        Where-Object { $existingIds -notcontains $_.Id } |
        Select-Object -First 1

    if (-not $proc) { Start-Sleep -Milliseconds 250 }
}

if ($proc) {
    Write-Host "Waiting for App Installer to finish..."
    $proc.WaitForExit()
}
else {
    Write-Warning "App Installer did not appear within $appearTimeout s; not waiting."
}

# App Installer can exit slightly before deployment finishes -- and the user may
# close its window the moment it reports success. Confirm registration before
# letting the SFX delete the package out from under it.

if ($identityName) {

    Write-Host "Confirming package registration..."

    $registered = $null
    $deadline = (Get-Date).AddSeconds(60)

    while (-not $registered -and (Get-Date) -lt $deadline) {

        $registered = Get-AppxPackage -Name $identityName -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if (-not $registered) { Start-Sleep -Milliseconds 500 }
    }

    if ($registered) {
        Write-Host "Installed: $($registered.Name) $($registered.Version)"
    }
    else {
        Write-Warning "Package '$identityName' is not registered. The install may have been cancelled or may have failed."
    }
}
else {
    # Without an identity name there is nothing to poll, so allow a short grace
    # period for deployment to finish reading the file.
    Start-Sleep -Seconds 3
}
