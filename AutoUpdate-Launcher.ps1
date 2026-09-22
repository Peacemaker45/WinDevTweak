function Fix-LocalPatches {
    param([string]$targetDir)
    
    # 1. Patch XAML
    $xPath = Join-Path $targetDir "Modules\UI.xaml"
    if (Test-Path $xPath) {
        $x = Get-Content $xPath -Raw
        $x = $x -replace '\s*MouseLeftButtonDown="[^"]*"', ''
        $x = $x -replace '\s*LetterSpacing="[^"]*"', ''
        Set-Content -Path $xPath -Value $x -Encoding utf8
    }

    # 2. Patch UI.ps1 pipeline leaks
    $uiPath = Join-Path $targetDir "Modules\UI.ps1"
    if (Test-Path $uiPath) {
        $ui = Get-Content $uiPath -Raw
        $ui = $ui.Replace('$sp.Children.Add($tbName)', '[void]$sp.Children.Add($tbName)')
        $ui = $ui.Replace('$sp.Children.Add($tbRisk)', '[void]$sp.Children.Add($tbRisk)')
        $ui = $ui.Replace('$sp.Children.Add($tbDesc)', '[void]$sp.Children.Add($tbDesc)')
        $ui = $ui.Replace('$sp.Children.Add($tbId)', '[void]$sp.Children.Add($tbId)')
        $ui = $ui.Replace('$CategoryList.Items.Add($allItem)', '[void]$CategoryList.Items.Add($allItem)')
        $ui = $ui.Replace('$CategoryList.Items.Add($item)', '[void]$CategoryList.Items.Add($item)')
        Set-Content -Path $uiPath -Value $ui -Encoding utf8
    }

    # 3. Patch Engine.ps1 fallback
    $engPath = Join-Path $targetDir "Modules\Engine.ps1"
    if (Test-Path $engPath) {
        $eng = Get-Content $engPath -Raw
        $oldImport = 'Import-PowerShellDataFile -Path $path'
        $newImport = 'if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) { Import-PowerShellDataFile -Path $path } else { & ([scriptblock]::Create((Get-Content -Path $path -Raw))) }'
        if ($eng.Contains($oldImport)) {
            $eng = $eng.Replace($oldImport, $newImport)
            Set-Content -Path $engPath -Value $eng -Encoding utf8
        }
    }
}

# Run immediately for local files
Fix-LocalPatches -targetDir $PSScriptRoot

Write-Host "Checking GitHub for WinDevTweak updates..." -ForegroundColor Cyan

try {
    git fetch origin master --quiet 2>$null
    $localCommit = git rev-parse HEAD 2>$null
    $remoteCommit = git rev-parse origin/master 2>$null

    if ($localCommit -and $remoteCommit -and ($localCommit -ne $remoteCommit)) {
        Write-Host "New update detected on GitHub! Updating safely..." -ForegroundColor Yellow
        git reset --hard origin/master --quiet
        git pull origin master --quiet
        Fix-LocalPatches -targetDir $PSScriptRoot
        Write-Host "Successfully updated and auto-patched." -ForegroundColor Green
    } else {
        Write-Host "WinDevTweak is up to date." -ForegroundColor Green
    }
} catch {
    Write-Warning "Could not check updates (offline or git error). Using local files."
}

# Launch the tool
$targetScript = if ($PSScriptRoot) { Join-Path $PSScriptRoot "WinDevTweak.ps1" } else { Join-Path (Get-Location) "WinDevTweak.ps1" }
& $targetScript

