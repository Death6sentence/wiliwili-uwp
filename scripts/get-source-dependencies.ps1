$ErrorActionPreference = "Stop"

$borealisRepo = "https://github.com/ikas-mc/borealis.git"
$borealisRef = "winrt-dev"
$borealisCommit = "789b230cb4e50ff2098ae872a6bfe3f1d835f25b"
# The original ikas-mc fork is unavailable. Fetch the same object from its fork network.
$wiliwiliRepo = "https://github.com/xfangfang/wiliwili.git"
$wiliwiliRef = "winrt-dev"
$wiliwiliCommit = "ff43110e224c822f527f8c3dd0fb96eba9c3c827"

function Ensure-GitCheckout {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    if (-not (Test-Path $Path)) {
        & git init --quiet $Path
        if ($LASTEXITCODE -ne 0) { throw "git init failed for $Path" }
    }
    if (-not (Test-Path (Join-Path $Path ".git"))) {
        throw "$Path exists but is not a Git checkout"
    }

    Push-Location $Path
    try {
        $changes = & git status --porcelain
        if ($LASTEXITCODE -ne 0 -or $changes) {
            throw "$Path could not be checked or has local changes"
        }

        Write-Host "Fetching $Path ($Ref) at $Commit from $Repo"
        & git fetch --depth 1 $Repo $Commit
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed for $Path at $Commit" }

        & git checkout --detach $Commit
        if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $Path at $Commit" }

        $actualCommit = & git rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $Commit) {
            throw "$Path checkout mismatch: expected $Commit but got $actualCommit"
        }
    }
    finally {
        Pop-Location
    }
}

Ensure-GitCheckout -Path "borealis" -Repo $borealisRepo -Ref $borealisRef -Commit $borealisCommit
Ensure-GitCheckout -Path "wiliwili" -Repo $wiliwiliRepo -Ref $wiliwiliRef -Commit $wiliwiliCommit

& git -C wiliwili submodule update --init --depth 1 -- "library/libpdr" "library/pystring" "library/mongoose"
if ($LASTEXITCODE -ne 0) { throw "wiliwili submodule update failed" }
& git -C wiliwili submodule status -- "library/libpdr" "library/pystring" "library/mongoose"
if ($LASTEXITCODE -ne 0) { throw "git submodule status failed" }
