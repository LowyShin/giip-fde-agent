<#
.SYNOPSIS
    Fetch or search design systems from designmd.ai.
.DESCRIPTION
    A wrapper around npx designmd to simplify discovery and download of DESIGN.md files.
.PARAMETER Action
    Can be 'search', 'download', or 'trending'.
.PARAMETER Query
    The search term or kit-id.
.EXAMPLE
    .\mgmt\fetchDesignMD.ps1 -Action search -Query "minimal dark"
    .\mgmt\fetchDesignMD.ps1 -Action download -Query "shafius/neon-fintech"
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("search", "download", "trending")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$Query
)

Write-Host "--- DesignMD Integration ---" -ForegroundColor Cyan

if ($Action -eq "trending") {
    Write-Host "Fetching trending kits..."
    npx -y designmd search "trending" --json
}
elseif ($Action -eq "search") {
    if (-not $Query) { throw "Query is required for search." }
    Write-Host "Searching for '$Query'..."
    npx -y designmd search "$Query" --json
}
elseif ($Action -eq "download") {
    if (-not $Query) { throw "Kit ID (Query) is required for download." }
    Write-Host "Downloading '$Query' to ./DESIGN.md..."
    npx -y designmd download $Query -o ./DESIGN.md
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Success! DESIGN.md created." -ForegroundColor Green
    } else {
        Write-Host "Failed to download. Check Kit ID or DESIGNMD_API_KEY." -ForegroundColor Red
    }
}
