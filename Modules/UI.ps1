Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptPath\Engine.ps1"

$config = Import-TweaksConfig

[xml]$xaml = Get-Content "$scriptPath\UI.xaml"
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$CategoryList = $window.FindName('CategoryList')
$TweakPanel = $window.FindName('TweakPanel')
$LogBox = $window.FindName('LogBox')
$BtnSelectAll = $window.FindName('BtnSelectAll')
$BtnDeselectAll = $window.FindName('BtnDeselectAll')
$BtnRestorePoint = $window.FindName('BtnRestorePoint')
$BtnUndo = $window.FindName('BtnUndo')
$BtnSaveProfile = $window.FindName('BtnSaveProfile')
$BtnLoadProfile = $window.FindName('BtnLoadProfile')
$BtnApply = $window.FindName('BtnApply')
$BtnMinimize = $window.FindName('BtnMinimize')
$BtnClose = $window.FindName('BtnClose')
$ProgressBar = $window.FindName('ProgressBar')
$SelectionLabel = $window.FindName('SelectionLabel')
$StatusLabel = $window.FindName('StatusLabel')
$SearchBox = $window.FindName('SearchBox')

$script:Checkboxes = @{}
$script:Cards = @{}
$script:CurrentFilter = ''
$script:CurrentCategory = $null

$tweakCounts = @{}
foreach ($t in $config.Tweaks) {
    if (-not $tweakCounts.ContainsKey($t.Category)) { $tweakCounts[$t.Category] = 0 }
    $tweakCounts[$t.Category]++
}

function Update-SelectionLabel {
    $selected = $script:Checkboxes.Values | Where-Object { $_.IsChecked -eq $true }
    $count = if ($selected) { $selected.Count } else { 0 }
    if ($SelectionLabel) {
        $SelectionLabel.Text = "$count selected"
        $SelectionLabel.Foreground = if ($count -gt 0) { '#2ea043' } else { '#484f58' }
    }
}

function New-TweakCard {
    param([hashtable]$Tweak)
    
    $border = New-Object System.Windows.Controls.Border
    $border.Width = 360
    $border.Margin = '8'
    $border.Padding = '16'
    $border.CornerRadius = '4'
    $border.Background = '#21262d'
    $border.BorderBrush = '#30363d'
    $border.BorderThickness = '1'
    $border.Cursor = 'Hand'
    
    $border.Add_MouseEnter({
        $this.BorderBrush = '#8b949e'
        $this.Background = '#1c2128'
    })
    $border.Add_MouseLeave({
        if ($script:Checkboxes[$this.Tag].IsChecked -ne $true) {
            $this.BorderBrush = '#30363d'
            $this.Background = '#21262d'
        }
    })
    
    $grid = New-Object System.Windows.Controls.Grid
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='Auto'}))
    $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition -Property @{Width='*'}))
    
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Margin = '0,2,14,0'
    $cb.VerticalAlignment = 'Top'
    $cb.Tag = $Tweak.Id
    $cb.Add_Checked({
        Update-SelectionLabel
        $id = $this.Tag
        if ($script:Cards.ContainsKey($id)) {
            $script:Cards[$id].BorderBrush = '#2ea043'
            $script:Cards[$id].BorderThickness = '2'
            $script:Cards[$id].Background = '#1c2128'
        }
    })
    $cb.Add_Unchecked({
        Update-SelectionLabel
        $id = $this.Tag
        if ($script:Cards.ContainsKey($id)) {
            $script:Cards[$id].BorderBrush = '#30363d'
            $script:Cards[$id].BorderThickness = '1'
            $script:Cards[$id].Background = '#21262d'
        }
    })
    [void]$grid.Children.Add($cb)
    [System.Windows.Controls.Grid]::SetColumn($cb, 0)
    
    $sp = New-Object System.Windows.Controls.StackPanel
    $tbName = New-Object System.Windows.Controls.TextBlock
    $tbName.Text = $Tweak.Name
    $tbName.FontWeight = 'SemiBold'
    $tbName.FontSize = 13
    $tbName.Foreground = switch ($Tweak.RiskLevel) {
        'High'   { '#f85149' }
        'Medium' { '#d29922' }
        default  { '#e6edf3' }
    }
    [void][void][void][void]$sp.Children.Add($tbName)
    
    if ($Tweak.RiskLevel -ne 'Low') {
        $tbRisk = New-Object System.Windows.Controls.TextBlock
        $tbRisk.Text = "$($Tweak.RiskLevel.ToUpper()) RISK"
        $tbRisk.Foreground = if ($Tweak.RiskLevel -eq 'High') { '#f85149' } else { '#d29922' }
        $tbRisk.FontSize = 9
        $tbRisk.FontWeight = 'Bold'
        $tbRisk.Margin = '0,4,0,0'
        $tbRisk.Opacity = 0.9
        [void][void][void][void]$sp.Children.Add($tbRisk)
    }
    
    $tbDesc = New-Object System.Windows.Controls.TextBlock
    $tbDesc.Text = $Tweak.Description
    $tbDesc.Foreground = '#8b949e'
    $tbDesc.FontSize = 11
    $tbDesc.TextWrapping = 'Wrap'
    $tbDesc.Margin = '0,6,0,0'
    $tbDesc.LineHeight = 16
    [void][void][void][void]$sp.Children.Add($tbDesc)
    
    $tbId = New-Object System.Windows.Controls.TextBlock
    $tbId.Text = $Tweak.Id
    $tbId.Foreground = '#484f58'
    $tbId.FontSize = 9
    $tbId.Margin = '0,8,0,0'
    $tbId.FontFamily = 'Cascadia Mono, Consolas'
    [void][void][void][void]$sp.Children.Add($tbId)
    
    [void]$grid.Children.Add($sp)
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    
    $border.Child = $grid
    $border.Tag = $Tweak.Id
    
    $script:Checkboxes[$Tweak.Id] = $cb
    $script:Cards[$Tweak.Id] = $border
    
    return $border
}

function Show-Tweaks {
    param(
        [string]$CategoryId,
        [string]$Filter = ''
    )
    $TweakPanel.Children.Clear()
    $script:Checkboxes.Clear()
    $script:Cards.Clear()
    
    $filtered = if ($CategoryId) {
        $config.Tweaks | Where-Object { $_.Category -eq $CategoryId }
    } else {
        $config.Tweaks
    }
    
    if ($Filter) {
        $q = $Filter.ToLower()
        $filtered = $filtered | Where-Object { $_.Name.ToLower().Contains($q) -or $_.Description.ToLower().Contains($q) -or $_.Id.ToLower().Contains($q) }
    }
    
    foreach ($tweak in $filtered) {
        $card = New-TweakCard -Tweak $tweak
        [void]$TweakPanel.Children.Add($card)
    }
    
    Update-SelectionLabel
    if ($StatusLabel) {
        $StatusLabel.Text = "$($filtered.Count) tweaks displayed"
    }
}

# Categories
$allItem = New-Object System.Windows.Controls.ListBoxItem
$allItem.Content = "All Tweaks"
$allItem.Tag = $null
$allItem.FontWeight = 'SemiBold'
$allItem.Foreground = '#e6edf3'
[void][void][void][void]$CategoryList.Items.Add($allItem)

foreach ($cat in $config.Categories) {
    $item = New-Object System.Windows.Controls.ListBoxItem
    $count = $tweakCounts[$cat.Id]
    $item.Content = "$($cat.Name)"
    $item.Tag = $cat.Id
    [void][void][void][void]$CategoryList.Items.Add($item)
}

$CategoryList.Add_SelectionChanged({
    $selected = $CategoryList.SelectedItem
    if ($selected) {
        # Visual selection indicator
        foreach ($it in $CategoryList.Items) {
            $it.Foreground = '#8b949e'
            $it.FontWeight = 'Normal'
            $it.BorderThickness = '0'
        }
        $selected.Foreground = '#e6edf3'
        $selected.FontWeight = 'SemiBold'
        $selected.BorderBrush = '#2ea043'
        $selected.BorderThickness = '4,0,0,0'
        $selected.Padding = '12,12,12,12'
        
        $script:CurrentCategory = $selected.Tag
        Show-Tweaks -CategoryId $selected.Tag -Filter $script:CurrentFilter
    }
})

# Search
$SearchBox.Add_GotFocus({
    if ($SearchBox.Text -eq 'Search tweaks...') {
        $SearchBox.Text = ''
        $SearchBox.Foreground = '#e6edf3'
    }
})
$SearchBox.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($SearchBox.Text)) {
        $SearchBox.Text = 'Search tweaks...'
        $SearchBox.Foreground = '#484f58'
    }
})
$SearchBox.Add_TextChanged({
    $query = $SearchBox.Text.Trim()
    if ($query -eq 'Search tweaks...') { $query = '' }
    $script:CurrentFilter = $query
    Show-Tweaks -CategoryId $script:CurrentCategory -Filter $query
})

# Window drag
$window.Add_MouseLeftButtonDown({
    param($sender, $e)
    if ($e.GetPosition($window).Y -lt 48) {
        $window.DragMove()
    }
})

# Title bar buttons
$BtnMinimize.Add_Click({ $window.WindowState = 'Minimized' })
$BtnClose.Add_Click({ $window.Close() })

# Toolbar buttons
$BtnSelectAll.Add_Click({ 
    foreach ($cb in $script:Checkboxes.Values) { $cb.IsChecked = $true }
})

$BtnDeselectAll.Add_Click({ 
    foreach ($cb in $script:Checkboxes.Values) { $cb.IsChecked = $false }
})

$BtnRestorePoint.Add_Click({
    $BtnRestorePoint.IsEnabled = $false
    New-SystemRestorePoint
    $BtnRestorePoint.IsEnabled = $true
})

$BtnUndo.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        'This will restore registry backups from the last Apply session. Continue?',
        'WinDevTweak - Undo',
        'YesNo',
        'Warning'
    )
    if ($result -eq 'Yes') {
        $BtnUndo.IsEnabled = $false
        Undo-LastSession -LogBox $LogBox
        $BtnUndo.IsEnabled = $true
    }
})

$BtnSaveProfile.Add_Click({
    $selectedIds = $script:Checkboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if (-not $selectedIds) {
        Write-Log 'No tweaks selected to save.' -Level Warning -LogBox $LogBox
        return
    }
    $profile = @{
        Version = '1.1.0'
        Created = (Get-Date -Format 'o')
        Tweaks = @($selectedIds)
    }
    $savePath = Join-Path $env:USERPROFILE 'Documents\WinDevTweak_Profile.json'
    $profile | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 $savePath
    Write-Log "Profile saved to: $savePath" -Level Success -LogBox $LogBox
})

$BtnLoadProfile.Add_Click({
    $openFile = New-Object Microsoft.Win32.OpenFileDialog
    $openFile.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $openFile.InitialDirectory = Join-Path $env:USERPROFILE 'Documents'
    if ($openFile.ShowDialog() -eq $true) {
        try {
            $profile = Get-Content $openFile.FileName | ConvertFrom-Json
            foreach ($id in $profile.Tweaks) {
                if ($script:Checkboxes.ContainsKey($id)) {
                    $script:Checkboxes[$id].IsChecked = $true
                }
            }
            Write-Log "Profile loaded: $($openFile.FileName)" -Level Success -LogBox $LogBox
        } catch {
            Write-Log "Failed to load profile: $_" -Level Error -LogBox $LogBox
        }
    }
})

$BtnApply.Add_Click({
    $selected = $script:Checkboxes.Values | Where-Object { $_.IsChecked -eq $true }
    if (-not $selected) {
        Write-Log 'No tweaks selected.' -Level Warning -LogBox $LogBox
        return
    }
    
    $result = [System.Windows.MessageBox]::Show(
        "You are about to apply $($selected.Count) tweak(s).`n`nCreate a System Restore Point first?",
        'WinDevTweak - Confirm',
        'YesNoCancel',
        'Question'
    )
    
    if ($result -eq 'Cancel') { return }
    if ($result -eq 'Yes') {
        New-SystemRestorePoint
    }
    
    Clear-Backups
    
    $BtnApply.IsEnabled = $false
    $BtnSelectAll.IsEnabled = $false
    $BtnDeselectAll.IsEnabled = $false
    $BtnUndo.IsEnabled = $false
    $ProgressBar.Visibility = 'Visible'
    $ProgressBar.Maximum = $selected.Count
    $ProgressBar.Value = 0
    
    $total = $selected.Count
    $current = 0
    foreach ($cb in $selected) {
        $current++
        $tweak = $config.Tweaks | Where-Object { $_.Id -eq $cb.Tag } | Select-Object -First 1
        Write-Log "[$current/$total] $($tweak.Name)" -Level Info -LogBox $LogBox
        $ok = Invoke-Tweak -Tweak $tweak -LogBox $LogBox
        if ($ok) { 
            $id = $cb.Tag
            if ($script:Cards.ContainsKey($id)) {
                $script:Cards[$id].Opacity = 0.5
                $script:Cards[$id].Background = '#161b22'
                $script:Cards[$id].BorderBrush = '#2ea043'
            }
            $cb.IsEnabled = $false
        }
        $ProgressBar.Value = $current
    }
    
    Write-Log 'All selected tweaks processed.' -Level Success -LogBox $LogBox
    $BtnApply.IsEnabled = $true
    $BtnSelectAll.IsEnabled = $true
    $BtnDeselectAll.IsEnabled = $true
    $BtnUndo.IsEnabled = $true
    $ProgressBar.Visibility = 'Collapsed'
})

# Init
Show-Tweaks -CategoryId $null
$CategoryList.SelectedIndex = 0
$SearchBox.Foreground = '#484f58'
Write-Log 'WinDevTweak v1.1.0 loaded. Select tweaks and click Apply.' -Level Info -LogBox $LogBox

[void]$window.ShowDialog()




