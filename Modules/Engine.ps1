#Requires -RunAsAdministrator

$script:BackupDir = "$env:TEMP\WinDevTweak\Backups"

function Import-TweaksConfig {
    $path = Join-Path $PSScriptRoot '..\Config\Tweaks.psd1'
    if (Get-Command Import-PowerShellDataFile -ErrorAction SilentlyContinue) {
        Import-PowerShellDataFile -Path $path
    } else {
        & ([scriptblock]::Create((Get-Content -Path $path -Raw)))
    }
}

function New-SystemRestorePoint {
    param([string]$Description = 'WinDevTweak_Backup')
    try {
        Invoke-WmiMethod -Namespace root\default -Class SystemRestore -Name CreateRestorePoint -ArgumentList $Description, 100, 7 | Out-Null
        Write-Log 'System Restore Point created successfully.' -Level Success
        return $true
    } catch {
        Write-Log "Failed to create System Restore Point: $_" -Level Error
        return $false
    }
}

function Backup-RegistryForTweak {
    param([hashtable]$Tweak)
    if (-not (Test-Path $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    }
    
    $uniquePaths = @{}
    foreach ($cmd in $Tweak.Commands) {
        if ($cmd -match 'reg(?:\.exe)?\s+add\s+"([^"]+)"') {
            $path = $matches[1]
            $fullPath = $path -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\' -replace '^HKCR\\', 'HKEY_CLASSES_ROOT\'
            $uniquePaths[$fullPath] = $true
        }
    }
    
    if ($uniquePaths.Count -eq 0) { return $true }
    
    $i = 0
    foreach ($fp in $uniquePaths.Keys) {
        $backupFile = Join-Path $script:BackupDir "$($Tweak.Id)_$i.reg"
        try {
            reg.exe export $fp $backupFile /y 2>$null | Out-Null
        } catch {
            # Ignore individual export failures
        }
        $i++
    }
    return $true
}

function Undo-LastSession {
    param([System.Windows.Controls.RichTextBox]$LogBox)
    if (-not (Test-Path $script:BackupDir)) {
        Write-Log 'No backups found to undo.' -Level Warning -LogBox $LogBox
        return $false
    }
    $backups = Get-ChildItem $script:BackupDir -Filter '*.reg' | Sort-Object Name -Descending
    if ($backups.Count -eq 0) {
        Write-Log 'No backup files found.' -Level Warning -LogBox $LogBox
        return $false
    }
    Write-Log "Undoing $($backups.Count) backup(s)..." -Level Info -LogBox $LogBox
    foreach ($b in $backups) {
        try {
            $output = reg.exe import $b.FullName 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
            Write-Log "Restored: $($b.Name)" -Level Success -LogBox $LogBox
        } catch {
            Write-Log "Failed to restore $($b.Name): $_" -Level Error -LogBox $LogBox
        }
    }
    Write-Log 'Undo completed. A restart may be required.' -Level Success -LogBox $LogBox
    return $true
}

function Clear-Backups {
    if (Test-Path $script:BackupDir) {
        Remove-Item "$script:BackupDir\*.reg" -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Tweak {
    param(
        [hashtable]$Tweak,
        [System.Windows.Controls.RichTextBox]$LogBox,
        [switch]$NoBackup
    )
    Write-Log "Applying: $($Tweak.Name)" -Level Info -LogBox $LogBox
    if (-not $NoBackup) {
        Backup-RegistryForTweak -Tweak $Tweak
    }
    $success = $true
    foreach ($cmd in $Tweak.Commands) {
        try {
            $output = Invoke-Expression $cmd 2>&1
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                throw "Exit code: $LASTEXITCODE"
            }
            if ($output) {
                Write-Log "  OUT: $output" -Level Info -LogBox $LogBox
            }
            Write-Log "  OK" -Level Success -LogBox $LogBox
        } catch {
            Write-Log "  FAIL: $_" -Level Error -LogBox $LogBox
            $success = $false
        }
    }
    return $success
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')]
        [string]$Level = 'Info',
        [System.Windows.Controls.RichTextBox]$LogBox
    )
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $fullMsg = "[$timestamp] $Message"
    
    if ($LogBox) {
        $LogBox.Dispatcher.Invoke([action]{
            $para = New-Object System.Windows.Documents.Paragraph
            $run = New-Object System.Windows.Documents.Run($fullMsg)
            switch ($Level) {
                'Success' { $run.Foreground = [System.Windows.Media.Brushes]::LimeGreen }
                'Warning' { $run.Foreground = [System.Windows.Media.Brushes]::Yellow }
                'Error'   { $run.Foreground = [System.Windows.Media.Brushes]::Red }
                default   { $run.Foreground = [System.Windows.Media.Brushes]::LightGray }
            }
            $para.Inlines.Add($run)
            $LogBox.Document.Blocks.Add($para)
            $LogBox.ScrollToEnd()
        })
    } else {
        switch ($Level) {
            'Success' { Write-Host $fullMsg -ForegroundColor Green }
            'Warning' { Write-Host $fullMsg -ForegroundColor Yellow }
            'Error'   { Write-Host $fullMsg -ForegroundColor Red }
            default   { Write-Host $fullMsg }
        }
    }
}







