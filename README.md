# Remove-Apps

Press a hotkey to fully remove **TightVNC** and **Tailscale** from Windows: uninstall, leftover files, registry keys, and firewall rules.

> ⚠️ Runs instantly with no confirmation. Deletions are permanent. If you're connected through Tailscale or TightVNC, you'll be cut off.

## Setup (one time)

1. Double-click `Setup-Hotkey.bat`.
2. Click **Yes** on the admin prompt.
3. Wait for **"Setup complete."**

## Usage

Press **Ctrl + Shift + Alt + R**. It runs silently with no prompts. Check the result in:

```
C:\Program Files\RemoveApps\last-run.log
```

## Changing the hotkey

Edit `$Hotkey` near the top of the PowerShell section in `Setup-Hotkey.bat` (after `#PSSTART`), then re-run the setup.

## Adding another app

1. Open `Setup-Hotkey.bat` in Notepad and find the `$Apps` list.
2. Add an entry (separate entries with a comma):

   ```powershell
   @{ Name = "AppName"; Services = @("serviceName"); Processes = @("processName*");
      Registry = @("HKLM:\SOFTWARE\...") }
   ```

   `Services`, `Processes`, and `Registry` can be `@()` if unknown.
3. Save, then **re-run `Setup-Hotkey.bat`**. Editing the file alone changes nothing.

## Notes

- Matching is partial (`*AppName*`), so use a specific name.
- Files are deleted for **all user profiles**.
- Exit code `3010` means success; a restart is needed.

## Uninstall the hotkey setup

In an admin PowerShell:

```powershell
schtasks /delete /tn RemoveAppsSilent /f
Remove-Item "$env:ProgramFiles\RemoveApps" -Recurse -Force
Remove-Item "$([Environment]::GetFolderPath('StartMenu'))\Programs\Remove Apps (hotkey).lnk"
```
