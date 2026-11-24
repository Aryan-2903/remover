# Remove-Apps

Quick script to fully remove an app from Windows — uninstall, leftover files, registry, the works. No manual cleanup after.

## What it does

- Kills the app's processes and services
- Runs the real uninstaller silently (MSI, EXE, winget, Store apps — whatever applies)
- Deletes leftover folders in Program Files, AppData, ProgramData, Start Menu
- Removes firewall rules and registry keys it left behind

Currently set up for **TightVNC** and **Tailscale**. Add more apps by editing the list at the top of the script.

## How to run it

Double-click `Remove-Apps.bat`. Click Yes on the admin prompt. That's it.

Prefer cmd? Open an admin Command Prompt, `cd` to the folder, and run:
```
Remove-Apps.bat
```

## Adding another app

Open the `.bat` in Notepad, find the `$Apps` list near the top, and add a block like:

```powershell
@{ Name = "AppName"; Services = @("serviceName"); Processes = @("processName*");
   Registry = @("HKLM:\SOFTWARE\...") }
```

`Services` and `Processes` and `Registry` can be left as empty arrays `@()` if you don't know them — the script still handles the generic uninstall + file cleanup either way.

## Notes

- Matching is partial name-based (`*AppName*`), so pick a specific enough name or it'll grab more than intended.
- Deletions are permanent — no recycle bin.
- Exit code `3010` from an uninstaller means success, just needs a restart to fully clear.
- If you added VPN/remote-access tools to the list, running it will obviously kill your own connection if you're on one.

## Hotkey version

`Setup-Hotkey.bat` registers this as a background Scheduled Task (runs elevated, no prompt) and binds it to a hotkey via a Start Menu shortcut. Run it once, then the hotkey (default `Ctrl+Shift+Alt+R`, edit at the top of the file) runs the cleanup silently. Log of the last run: `C:\Program Files\RemoveApps\last-run.log`.
