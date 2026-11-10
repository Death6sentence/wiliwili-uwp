#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackagePath,
    [Parameter(Mandatory)][string]$MakeAppx,
    [Parameter(Mandatory)][string]$PackageVersion
)

$ErrorActionPreference = 'Stop'
$expectedName = 'Ralinfr.BilibiliforXbox'
$expectedPublisher = 'CN=51C44227-390E-4AC6-ACAA-ABF4CEE83F30'
$expectedFamilies = @{
    'Windows.Universal' = '10.0.17763.0'
    'Windows.Xbox' = '10.0.19041.0'
}

function Assert-PackageIdentity {
    param($Identity, [string]$Label)
    if ($Identity.Name -cne $expectedName -or $Identity.Publisher -cne $expectedPublisher -or
        $Identity.Version -cne $PackageVersion) {
        throw "$Label does not have the expected package identity/version."
    }
}

function Invoke-MakeAppx {
    param([string[]]$Arguments)
    & $MakeAppx @Arguments
    if ($LASTEXITCODE -ne 0) { throw "MakeAppx failed with exit code $LASTEXITCODE" }
}

function Read-PackageXml {
    param([IO.Compression.ZipArchive]$Archive, [string]$Name)
    $entry = $Archive.GetEntry($Name)
    if (-not $entry) { throw "Missing ZIP entry: $Name" }
    $stream = $entry.Open()
    try {
        $document = [xml]::new()
        $document.XmlResolver = $null
        $document.Load($stream)
        return $document
    }
    finally {
        $stream.Dispose()
    }
}

function Assert-BlockMap {
    param([string]$Path)
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if (-not $archive.GetEntry('[Content_Types].xml')) { throw "Missing content types in $Path" }
        $blockMap = Read-PackageXml $archive 'AppxBlockMap.xml'
        if ($blockMap.BlockMap.HashMethod -cne 'http://www.w3.org/2001/04/xmlenc#sha256') {
            throw "Unexpected block-map algorithm in $Path"
        }
        $buffer = [byte[]]::new(65536)
        foreach ($file in $blockMap.BlockMap.File) {
            $entry = $archive.GetEntry($file.Name.Replace('\', '/'))
            if (-not $entry -or $entry.Length -ne [long]$file.Size) {
                throw "Missing file or size mismatch in block map: $($file.Name)"
            }
            $stream = $entry.Open()
            $sha256 = [Security.Cryptography.SHA256]::Create()
            try {
                $remaining = $entry.Length
                foreach ($block in $file.Block) {
                    $size = [int][Math]::Min($remaining, $buffer.Length)
                    $stream.ReadExactly($buffer, 0, $size)
                    $hash = [Convert]::ToBase64String($sha256.ComputeHash($buffer, 0, $size))
                    if ($hash -cne $block.Hash) { throw "Block hash mismatch: $($file.Name)" }
                    $remaining -= $size
                }
                if ($remaining -ne 0) { throw "Incomplete block map for $($file.Name)" }
            }
            finally {
                $sha256.Dispose()
                $stream.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Assert-X64Executable {
    param([string]$Path)
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw "Missing MZ header: $Path" }
        $reader.BaseStream.Position = 0x3c
        $reader.BaseStream.Position = $reader.ReadUInt32()
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Invalid or non-x64 PE header: $Path"
        }
    }
    finally {
        $reader.Dispose()
    }
}

$package = Get-Item -LiteralPath $PackagePath
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('wiliwili-verify-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
try {
    $payload = $package
    if ($package.Extension -in '.appxupload', '.msixupload') {
        $uploadDir = Join-Path $scratch 'upload'
        [IO.Compression.ZipFile]::ExtractToDirectory($package.FullName, $uploadDir)
        $contents = @(Get-ChildItem -LiteralPath $uploadDir -File -Recurse | Where-Object Extension -in '.appx', '.msix', '.appxbundle', '.msixbundle')
        if ($contents.Count -ne 1) { throw "Expected one payload in upload container, found $($contents.Count)." }
        $payload = $contents[0]
    }

    $bundleFile = $null
    if ($payload.Extension -in '.appxbundle', '.msixbundle') {
        $bundleFile = $payload.Name
        $bundleDir = Join-Path $scratch 'bundle'
        Invoke-MakeAppx @('unbundle', '/p', $payload.FullName, '/d', $bundleDir, '/o')
        Assert-BlockMap $payload.FullName
        $bundleArchive = [IO.Compression.ZipFile]::OpenRead($payload.FullName)
        try {
            $bundleManifest = Read-PackageXml $bundleArchive 'AppxMetadata/AppxBundleManifest.xml'
        }
        finally {
            $bundleArchive.Dispose()
        }
        $bundlePackages = Get-ChildItem -LiteralPath $bundleDir -File -Recurse
        Assert-PackageIdentity $bundleManifest.Bundle.Identity 'Bundle'
        $application = @($bundleManifest.Bundle.Packages.Package | Where-Object Type -eq 'application')
        if ($application.Count -ne 1 -or $application[0].Architecture -cne 'x64') {
            throw 'Expected precisely one x64 application package in the bundle.'
        }
        foreach ($resource in @($bundleManifest.Bundle.Packages.Package | Where-Object Type -eq 'resource')) {
            $resourceFile = @($bundlePackages | Where-Object Name -ceq $resource.FileName)
            if ($resourceFile.Count -ne 1) { throw "Missing or duplicate resource package: $($resource.FileName)" }
            Assert-BlockMap $resourceFile[0].FullName
            Invoke-MakeAppx @('unpack', '/p', $resourceFile[0].FullName,
                '/d', (Join-Path $scratch ('resource-' + [guid]::NewGuid())), '/o')
        }
        $appPackage = @($bundlePackages | Where-Object Name -ceq $application[0].FileName)
        if ($appPackage.Count -ne 1) { throw 'Missing or duplicate application package in bundle.' }
        $payload = $appPackage[0]
    }

    Assert-BlockMap $payload.FullName
    $appDir = Join-Path $scratch 'app'
    Invoke-MakeAppx @('unpack', '/p', $payload.FullName, '/d', $appDir, '/o')
    $finalManifest = Join-Path $appDir 'AppxManifest.xml'
    [xml]$manifest = Get-Content -LiteralPath $finalManifest -Raw
    $identity = $manifest.Package.Identity
    Assert-PackageIdentity $identity 'Application'
    if ($identity.ProcessorArchitecture -cne 'x64' -or
        $manifest.Package.Properties.PublisherDisplayName -cne 'Ralinfr') {
        throw 'Invalid architecture or PublisherDisplayName in application manifest.'
    }

    $families = @($manifest.Package.Dependencies.TargetDeviceFamily)
    if ($families.Count -ne $expectedFamilies.Count) { throw 'Unexpected number of TargetDeviceFamily entries.' }
    $seenFamilies = @{}
    foreach ($family in $families) {
        if ($seenFamilies.ContainsKey($family.Name) -or $family.MinVersion -cne $expectedFamilies[$family.Name] -or
            $family.MaxVersionTested -cne '10.0.22621.0') {
            throw "Unexpected device-family settings: $($family.OuterXml)"
        }
        $seenFamilies[$family.Name] = $true
    }

    $app = $manifest.Package.Applications.Application
    if ($app.Id -cne 'App' -or $app.Executable -cne 'wiliwili-uwp.exe' -or $app.EntryPoint -cne 'wiliwili-uwp.App') {
        throw 'Unexpected UWP application entry point.'
    }
    $capabilities = @($manifest.Package.Capabilities.ChildNodes | Where-Object NodeType -eq 'Element' |
        ForEach-Object { $_.GetAttribute('Name') })
    if ($capabilities.Count -ne 2 -or 'internetClient' -cnotin $capabilities -or
        'backgroundMediaPlayback' -cnotin $capabilities) {
        throw "Unexpected application capabilities: $($capabilities -join ', ')"
    }
    foreach ($binary in @($app.Executable, 'mpv-2.dll', 'wasapiuwp2.dll')) {
        Assert-X64Executable (Join-Path $appDir $binary)
    }
    $hash = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $report = [ordered]@{
        File = $package.Name
        Path = $package.FullName
        Format = $package.Extension
        SizeBytes = $package.Length
        SHA256 = $hash
        Bundle = $bundleFile
        AppPackage = $payload.Name
        Name = $identity.Name
        Publisher = $identity.Publisher
        PublisherDisplayName = $manifest.Package.Properties.PublisherDisplayName
        Version = $identity.Version
        ProcessorArchitecture = $identity.ProcessorArchitecture
        TargetDeviceFamilies = @($families | ForEach-Object {
            [ordered]@{ Name = $_.Name; MinVersion = $_.MinVersion; MaxVersionTested = $_.MaxVersionTested }
        })
        Executable = $app.Executable
        EntryPoint = $app.EntryPoint
        Capabilities = $capabilities
        MakeAppx = $MakeAppx
    }
    Copy-Item -LiteralPath $finalManifest -Destination (Join-Path $package.DirectoryName 'AppxManifest.xml')
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $package.DirectoryName 'verification.json') -Encoding utf8
    "$hash  $($package.Name)" | Set-Content -LiteralPath (Join-Path $package.DirectoryName 'SHA256SUMS.txt') -Encoding ascii
    Write-Host "Verified $($package.Name): $($package.Length) bytes; SHA256 $hash"
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
