#Requires -Version 7.4
[CmdletBinding()]
param(
    [string]$PackageVersion = '1.6.0.0',
    [string]$SdkVersion = '10.0.22621.0',
    [string]$OutputRoot = 'build/store-results'
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'Store build requires Windows, Visual Studio 2022 C++ UWP tools and the Windows SDK.'
}
if ($PackageVersion -notmatch '^[1-9][0-9]{0,4}\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.0$' -or
    ($PackageVersion.Split('.') | Where-Object { [int]$_ -gt 65535 })) {
    throw 'PackageVersion must be Major.Minor.Build.0 (each component <= 65535, Major > 0).'
}

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    Write-Host ('> ' + $Program + ' ' + ($Arguments -join ' '))
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Push-Location $PSScriptRoot
try {
    $resultRoot = [IO.Path]::GetFullPath($OutputRoot, $PSScriptRoot)
    $logs = Join-Path $resultRoot 'logs'
    if (Test-Path $resultRoot) { throw "Output already exists: $resultRoot. Choose a new -OutputRoot." }
    $null = New-Item -ItemType Directory -Path $logs -Force
    Start-Transcript -Path (Join-Path $logs 'build-store.log')
    try {
        $makeAppx = Join-Path ${env:ProgramFiles(x86)} "Windows Kits/10/bin/$SdkVersion/x64/makeappx.exe"
        if (-not (Test-Path -LiteralPath $makeAppx)) { throw "Windows SDK MakeAppx missing: $makeAppx" }
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        $vsRoot = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.Component.MSBuild -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $vsRoot) { throw 'Visual Studio 2022 with MSBuild was not found.' }
        $msbuild = Join-Path $vsRoot 'MSBuild/Current/Bin/amd64/MSBuild.exe'
        Invoke-Checked $msbuild @('-version', '-nologo')
        Invoke-Checked 'cmake' @('--version')
        Write-Host "Windows SDK: $SdkVersion"
        Write-Host "Requested package version: $PackageVersion"
        if (Test-Path .git) { Invoke-Checked 'git' @('rev-parse', 'HEAD') }

        & ./scripts/get-source-dependencies.ps1

        $baseline = (Get-Content ./vcpkg-configuration.json -Raw | ConvertFrom-Json).'default-registry'.baseline
        $toolRoot = Join-Path $PSScriptRoot 'build/store-tools'
        $env:VCPKG_ROOT = Join-Path $toolRoot "vcpkg-$baseline"
        if (-not (Test-Path (Join-Path $env:VCPKG_ROOT '.git'))) {
            Invoke-Checked 'git' @('init', $env:VCPKG_ROOT)
            Invoke-Checked 'git' @('-C', $env:VCPKG_ROOT, 'remote', 'add', 'origin', 'https://github.com/microsoft/vcpkg.git')
        }
        Invoke-Checked 'git' @('-C', $env:VCPKG_ROOT, 'fetch', '--depth=1', 'origin', $baseline)
        Invoke-Checked 'git' @('-C', $env:VCPKG_ROOT, 'checkout', '--detach', $baseline)
        Invoke-Checked (Join-Path $env:VCPKG_ROOT 'bootstrap-vcpkg.bat') @('-disableMetrics')

        $mpvUrl = 'https://github.com/ikas-mc/wiliwili-uwp-poc/releases/download/0.4/x64-uwp-mpv.zip'
        $mpvSha256 = '82f8ce29700bf2c586d64c991f602b78c3e9a560c9094f07572db7f7e3ab7cef'
        $mpvZip = Join-Path $toolRoot 'x64-uwp-mpv.zip'
        if (-not (Test-Path -LiteralPath $mpvZip)) {
            $mpvDownload = "$mpvZip.download"
            Invoke-Checked 'curl.exe' @('--fail', '--location', '--retry', '3', '--output', $mpvDownload, $mpvUrl)
            if ((Get-FileHash -LiteralPath $mpvDownload -Algorithm SHA256).Hash -ne $mpvSha256) {
                throw 'Downloaded mpv archive SHA256 mismatch.'
            }
            Move-Item -LiteralPath $mpvDownload -Destination $mpvZip
        }
        if ((Get-FileHash -LiteralPath $mpvZip -Algorithm SHA256).Hash -ne $mpvSha256) {
            throw "Cached mpv archive SHA256 mismatch: $mpvZip"
        }
        Write-Host "Verified mpv SHA256: $mpvSha256"

        $buildDir = Join-Path $PSScriptRoot ('build/store-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $mpvRoot = Join-Path $buildDir 'mpv'
        Expand-Archive -LiteralPath $mpvZip -DestinationPath $mpvRoot
        foreach ($mpvFile in @('lib/mpv.lib', 'bin/mpv-2.dll', 'bin/wasapiuwp2.dll', 'include/mpv/client.h')) {
            if (-not (Test-Path -LiteralPath (Join-Path $mpvRoot $mpvFile))) { throw "Missing mpv file: $mpvFile" }
        }

        $manifestPath = Join-Path $buildDir 'store-input.appxmanifest'
        [xml]$manifest = Get-Content ./wiliwili-uwp/package.appxManifest -Raw
        $manifest.Package.Identity.Version = $PackageVersion
        $manifest.Save($manifestPath)

        $toolchain = Join-Path $env:VCPKG_ROOT 'scripts/buildsystems/vcpkg.cmake'
        try {
            Invoke-Checked 'cmake' @('--preset', 'uwp-release', '-B', $buildDir,
                '-A', "x64,version=$SdkVersion", "-DCMAKE_GENERATOR_INSTANCE=$vsRoot",
                "-DCMAKE_TOOLCHAIN_FILE=$toolchain", '-DWILIWILI_STORE_BUILD=ON',
                "-DWILIWILI_STORE_MANIFEST=$manifestPath", "-DWILIWILI_MPV_ROOT=$mpvRoot")
        }
        finally {
            Get-ChildItem -LiteralPath $buildDir -Filter 'vcpkg-manifest-install*.log' -File |
                Copy-Item -Destination $logs
            $configureLog = Join-Path $buildDir 'CMakeFiles/CMakeConfigureLog.yaml'
            if (Test-Path -LiteralPath $configureLog) { Copy-Item -LiteralPath $configureLog -Destination $logs }
        }

        $packageDir = Join-Path $buildDir 'AppPackages'
        $msbuildPackageDir = $packageDir.Replace('\', '/') + '/'
        Invoke-Checked $msbuild @((Join-Path $buildDir 'wiliwili-uwp.vcxproj'), '/m', '/nologo',
            '/p:Configuration=Release', '/p:Platform=x64',
            '/p:AppxBundle=Always', '/p:AppxBundlePlatforms=x64', "/p:AppxBundleVersion=$PackageVersion", '/p:UapAppxPackageBuildMode=StoreUpload',
            '/p:GenerateAppxPackageOnBuild=true', '/p:AppxPackageSigningEnabled=false',
            '/p:PackageCertificateKeyFile=', '/p:PackageCertificateThumbprint=',
            '/p:PackageOptionalProjectsInIdeBuilds=false', "/p:AppxPackageDir=$msbuildPackageDir",
            "/bl:$(Join-Path $logs 'msbuild.binlog')")

        $packages = @(Get-ChildItem -LiteralPath $packageDir -File -Recurse)
        $candidate = @($packages | Where-Object Extension -in '.appxupload', '.msixupload')
        if ($candidate.Count -eq 0) {
            Write-Warning 'MSBuild produced no StoreUpload container. Checking for a raw APPX/MSIX or bundle.'
            $candidate = @($packages | Where-Object Extension -in '.appxbundle', '.msixbundle')
            if ($candidate.Count -eq 0) {
                $candidate = @($packages | Where-Object {
                    $_.Extension -in '.appx', '.msix' -and $_.BaseName.EndsWith('_x64') -and
                    $_.DirectoryName -notmatch '[\\/]Dependencies([\\/]|$)'
                })
            }
        }
        if ($candidate.Count -ne 1) { throw "Expected one package candidate, found $($candidate.Count) in $packageDir" }

        $artifactDir = Join-Path $resultRoot 'package'
        $null = New-Item -ItemType Directory -Path $artifactDir
        $verifiedPackage = Join-Path $artifactDir $candidate[0].Name
        Copy-Item -LiteralPath $candidate[0].FullName -Destination $verifiedPackage
        try {
            & ./scripts/verify-store-package.ps1 -PackagePath $verifiedPackage -MakeAppx $makeAppx -PackageVersion $PackageVersion
        }
        catch {
            Remove-Item -LiteralPath $artifactDir -Recurse -Force
            throw
        }
    }
    finally {
        Stop-Transcript
    }
}
finally {
    Pop-Location
}
