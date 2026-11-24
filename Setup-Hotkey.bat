@echo off
if /i not "%~1"=="elevated" (
    fltmc >nul 2>&1 || (
        echo Requesting administrator rights ^(one time only^)...
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
        exit /b
    )
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content -LiteralPath '%~f0' -Raw; $m = '#PS' + 'START'; Invoke-Expression $c.Substring($c.LastIndexOf($m) + $m.Length)"
echo.
pause
exit /b
#PSSTART
$ErrorActionPreference = "Stop"

# ===================== EDIT IF YOU WANT A DIFFERENT HOTKEY =====================
$Hotkey = "CTRL+SHIFT+ALT+R"
# ===============================================================================

$TaskName = "RemoveAppsSilent"
$Dir      = Join-Path $env:ProgramFiles "RemoveApps"
New-Item -ItemType Directory -Path $Dir -Force | Out-Null

# 1. The cleanup script (silent run, output saved to last-run.log)
$payload = @'
$ErrorActionPreference = "SilentlyContinue"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "WARNING: not running as Administrator - uninstall will fail." -ForegroundColor Red }

# ---------- Apps to remove (add more entries here if needed) ----------
$Apps = @(
    @{ Name = "TightVNC";   Services = @("tvnserver"); Processes = @("tvn*");
       Registry = @("HKLM:\SYSTEM\CurrentControlSet\Services\tvnserver",
                    "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\TightVNC Server") },
    @{ Name = "Tailscale";  Services = @("Tailscale"); Processes = @("tailscale*");
       Registry = @("HKLM:\SOFTWARE\Tailscale IPN", "HKCU:\SOFTWARE\Tailscale IPN",
                    "HKLM:\SYSTEM\CurrentControlSet\Services\Tailscale") }
)
# -----------------------------------------------------------------------

$uninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Remove-FullApp($App) {
    $name = $App.Name
    $pattern = "*$name*"
    $installDirs = @()
    Write-Host "`n=============== $name ===============" -ForegroundColor Cyan

    # 1. Stop services and processes
    Write-Host "[1/6] Stopping services and processes..."
    foreach ($svc in $App.Services) { Stop-Service -Name $svc -Force }
    Get-Process | Where-Object { $_.Name -like $pattern } | Stop-Process -Force
    foreach ($proc in $App.Processes) { Get-Process -Name $proc | Stop-Process -Force }

    # 2. Run registered uninstallers
    Write-Host "[2/6] Running uninstallers..."
    $entries = Get-ItemProperty $uninstallRoots | Where-Object { $_.DisplayName -like $pattern }
    foreach ($e in $entries) {
        Write-Host "   Found: $($e.DisplayName)"
        if ($e.InstallLocation) { $installDirs += $e.InstallLocation }
        $p = $null
        if ($e.UninstallString -match "msiexec" -and $e.UninstallString -match "\{[0-9A-Fa-f-]+\}") {
            $guid = $Matches[0]
            Write-Host "   Running: msiexec /x $guid /qn /norestart"
            $p = Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru
        }
        elseif ($e.QuietUninstallString) {
            Write-Host "   Running: $($e.QuietUninstallString)"
            $p = Start-Process cmd.exe -ArgumentList "/c $($e.QuietUninstallString)" -Wait -PassThru -WindowStyle Hidden
        }
        elseif ($e.UninstallString) {
            Write-Host "   Running: $($e.UninstallString) (silent switches)"
            $p = Start-Process cmd.exe -ArgumentList "/c $($e.UninstallString) /VERYSILENT /SILENT /S /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru -WindowStyle Hidden
        }
        if ($p) { Write-Host "   Uninstaller exit code: $($p.ExitCode)" }
    }
    if (-not $entries) { Write-Host "   No installed entry found for $name (will still clean leftovers)." }

    # 3. Services, firewall rules, Store packages
    Write-Host "[3/6] Removing services, firewall rules, Store packages..."
    foreach ($svc in $App.Services) {
        sc.exe stop $svc | Out-Null
        sc.exe delete $svc | Out-Null
    }
    Get-NetFirewallRule -DisplayName $pattern | Remove-NetFirewallRule
    Get-AppxPackage -AllUsers $pattern | Remove-AppxPackage -AllUsers
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pattern } | Remove-AppxProvisionedPackage -Online

    # 4. winget fallback
    Write-Host "[4/6] winget fallback..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --name "$name" --silent --force --disable-interactivity --accept-source-agreements 2>$null | Out-Null
    }

    # 5. Leftover files, folders, shortcuts
    Write-Host "[5/6] Deleting leftover files..."
    $searchRoots = @(
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:PUBLIC\Desktop"
    )
    foreach ($u in (Get-ChildItem "C:\Users" -Directory)) {
        $searchRoots += "$($u.FullName)\AppData\Roaming"
        $searchRoots += "$($u.FullName)\AppData\Local"
        $searchRoots += "$($u.FullName)\AppData\Local\Programs"
        $searchRoots += "$($u.FullName)\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
        $searchRoots += "$($u.FullName)\Desktop"
    }
    foreach ($root in ($searchRoots | Where-Object { $_ -and (Test-Path $_) })) {
        Get-ChildItem $root -Force | Where-Object { $_.Name -like $pattern } | ForEach-Object {
            Write-Host "   Deleting $($_.FullName)"
            Remove-Item $_.FullName -Recurse -Force
        }
    }
    foreach ($d in ($installDirs | Select-Object -Unique)) {
        if ($d -and (Test-Path $d)) { Remove-Item $d -Recurse -Force }
    }

    # 6. Registry leftovers
    Write-Host "[6/6] Cleaning registry..."
    $regTargets = @("HKCU:\SOFTWARE\$name", "HKLM:\SOFTWARE\$name", "HKLM:\SOFTWARE\WOW6432Node\$name") + $App.Registry
    foreach ($r in $regTargets) { if (Test-Path $r) { Remove-Item $r -Recurse -Force } }
    foreach ($root in $uninstallRoots) {
        Get-ChildItem ($root -replace '\\\*$', '') | ForEach-Object {
            if ((Get-ItemProperty $_.PSPath).DisplayName -like $pattern) { Remove-Item $_.PSPath -Recurse -Force }
        }
    }
    Write-Host "'$name' removed." -ForegroundColor Green
}

foreach ($app in $Apps) { Remove-FullApp $app }

Write-Host "`nAll done." -ForegroundColor Green
'@
$ps1 = "Start-Transcript -Path `"$Dir\last-run.log`" -Force | Out-Null`r`n" + $payload + "`r`nStop-Transcript | Out-Null"
Set-Content -Path "$Dir\Remove-Apps.ps1" -Value $ps1 -Encoding UTF8

# 2. Scheduled task: runs elevated, on demand only (no UAC prompt when triggered)
$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\Remove-Apps.ps1`""
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

# 3. Invisible launcher (no console flash)
$vbs = 'CreateObject("WScript.Shell").Run "schtasks /run /tn ' + $TaskName + '", 0, False'
Set-Content -Path "$Dir\run-hidden.vbs" -Value $vbs -Encoding ASCII

# 4. Start Menu shortcut carrying the hotkey
$lnkPath = Join-Path ([Environment]::GetFolderPath("StartMenu")) "Programs\Remove Apps (hotkey).lnk"
$sh  = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.TargetPath  = "$env:WINDIR\System32\wscript.exe"
$lnk.Arguments   = "//B `"$Dir\run-hidden.vbs`""
$lnk.WindowStyle = 7
$lnk.Hotkey      = $Hotkey
$lnk.Save()

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Hotkey: $Hotkey  (runs silently, no prompts)"
Write-Host "Log of the last run: $Dir\last-run.log"
