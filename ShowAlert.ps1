# ==============================================================
#  ShowAlert.ps1  –  SELF-CONTAINED, no extra files needed
# ==============================================================
#
#  HOW TO CUSTOMISE
#  ----------------
#  1. Get Base64 of YOUR image (JPG/PNG/BMP):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\image.jpg"))
#
#  2. Get Base64 of YOUR sound (WAV):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\sound.wav"))
#
#  3. Run:
#       powershell -ExecutionPolicy Bypass -File ShowAlert.ps1
#
# ==============================================================

# ── SETTINGS ──────────────────────────────────────────────────
$DelaySeconds   = 30
$DisplaySeconds = 30
$ImageExt       = "bmp"
$SoundExt       = "wav"

# ── EMBEDDED IMAGE (Base64) ────────────────────────────────────
$IMAGE_B64 = ''

# ── EMBEDDED SOUND (Base64 WAV) ───────────────────────────────
$SOUND_B64 = ''

# ==============================================================

$log = "$env:TEMP\alert_log.txt"
function Log($msg) { "$(Get-Date -f 'HH:mm:ss') $msg" | Add-Content $log }
"" | Set-Content $log
Log "Script started"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Log "Assemblies loaded"

# ── Win32: ClipCursor ─────────────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Cursor {
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(IntPtr r);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# ── Low-level keyboard hook ───────────────────────────────────
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public class KeyboardBlocker {
    private static IntPtr hookId = IntPtr.Zero;
    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    private static LowLevelKeyboardProc proc = HookCallback;

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, LowLevelKeyboardProc cb, IntPtr hMod, uint tid);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int n, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern IntPtr GetModuleHandle(string name);

    public static void Install() {
        using (var cur = Process.GetCurrentProcess().MainModule)
            hookId = SetWindowsHookEx(13, proc, GetModuleHandle(cur.ModuleName), 0);
    }
    public static void Uninstall() { UnhookWindowsHookEx(hookId); }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0) return (IntPtr)1;
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }
}
"@

# ── FreeConsole (detach terminal AFTER assemblies loaded) ─────
Add-Type @"
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll")] public static extern bool FreeConsole();
}
"@

# ── 1. Decode files ───────────────────────────────────────────
$tmpImg   = [IO.Path]::Combine([IO.Path]::GetTempPath(), "alert_img.$ImageExt")
$tmpSound = [IO.Path]::Combine([IO.Path]::GetTempPath(), "alert_snd.$SoundExt")

try {
    [IO.File]::WriteAllBytes($tmpImg,   [Convert]::FromBase64String($IMAGE_B64))
    Log "Image written to $tmpImg ($(( [IO.File]::ReadAllBytes($tmpImg)).Length) bytes)"
} catch { Log "IMAGE DECODE FAILED: $_" }

try {
    [IO.File]::WriteAllBytes($tmpSound, [Convert]::FromBase64String($SOUND_B64))
    Log "Sound written to $tmpSound ($([IO.File]::ReadAllBytes($tmpSound).Length) bytes)"
} catch { Log "SOUND DECODE FAILED: $_" }

# ── 2. Wait ────────────────────────────────────────────────────
Log "Waiting $DelaySeconds seconds..."
Start-Sleep -Seconds $DelaySeconds
Log "Wait done"

# ── 3. Detach console now (just before UI) ────────────────────
[ConsoleHelper]::FreeConsole() | Out-Null
Log "Console freed"

# ── 4. Build fullscreen form ───────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = ""
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.WindowState     = [System.Windows.Forms.FormWindowState]::Maximized
$form.TopMost         = $true
$form.BackColor       = [System.Drawing.Color]::Black
$form.Cursor          = [System.Windows.Forms.Cursors]::None

try {
    $pb          = New-Object System.Windows.Forms.PictureBox
    $pb.Dock     = [System.Windows.Forms.DockStyle]::Fill
    $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
    $pb.Image    = [System.Drawing.Image]::FromFile($tmpImg)
    $form.Controls.Add($pb)
    Log "PictureBox loaded OK"
} catch { Log "IMAGE LOAD FAILED: $_" }

# ── 5. Sound via mciSendString (most reliable WAV+MP3 on Windows)
Add-Type @"
using System.Runtime.InteropServices;
public class MCI {
    [DllImport("winmm.dll", CharSet=CharSet.Auto)]
    public static extern int mciSendString(string cmd, string ret, int cch, int hwnd);
}
"@

$script:soundAlias = "alertsound"

function Start-MCISound {
    $path = $tmpSound -replace '\\', '\\'
    MCI::mciSendString("close $($script:soundAlias)", $null, 0, 0) | Out-Null
    $openResult = [MCI]::mciSendString("open `"$path`" type mpegvideo alias $($script:soundAlias)", $null, 0, 0)
    Log "MCI open result: $openResult"
    $playResult = [MCI]::mciSendString("play $($script:soundAlias) from 0", $null, 0, 0)
    Log "MCI play result: $playResult (0=success)"
}

# Looping timer — restarts sound when it ends
$soundTimer          = New-Object System.Windows.Forms.Timer
$soundTimer.Interval = 500
$soundTimer.Add_Tick({
    $status = New-Object System.Text.StringBuilder 64
    [MCI]::mciSendString("status $($script:soundAlias) mode", $status, 64, 0) | Out-Null
    if ($status.ToString().Trim() -eq "stopped") {
        [MCI]::mciSendString("play $($script:soundAlias) from 0", $null, 0, 0) | Out-Null
    }
})

$form.Add_Shown({
    Log "Form shown, starting sound"
    Start-MCISound
    $soundTimer.Start()

    # Lock mouse
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $rect   = New-Object Win32Cursor+RECT
    $rect.Left=$bounds.Left; $rect.Top=$bounds.Top
    $rect.Right=$bounds.Right; $rect.Bottom=$bounds.Bottom
    [Win32Cursor]::ClipCursor([ref]$rect) | Out-Null
    Log "Mouse locked"
})

# ── 6. Block keyboard ─────────────────────────────────────────
[KeyboardBlocker]::Install()
Log "Keyboard hook installed"

# ── 7. Prevent close ──────────────────────────────────────────
$script:allowClose = $false
$form.Add_FormClosing({
    if (-not $script:allowClose) { $_.Cancel = $true }
})

# ── 8. Auto-close timer ───────────────────────────────────────
$closeTimer          = New-Object System.Windows.Forms.Timer
$closeTimer.Interval = $DisplaySeconds * 1000
$closeTimer.Add_Tick({
    $closeTimer.Stop()
    $soundTimer.Stop()
    $script:allowClose = $true
    Log "Auto-closing"
    $form.Close()
})
$closeTimer.Start()

# ── 9. Run ────────────────────────────────────────────────────
Log "Entering Application.Run"
[System.Windows.Forms.Application]::Run($form)

# ── 10. Cleanup ───────────────────────────────────────────────
[KeyboardBlocker]::Uninstall()
[MCI]::mciSendString("close $($script:soundAlias)", $null, 0, 0) | Out-Null
[Win32Cursor]::ClipCursor([System.IntPtr]::Zero) | Out-Null
try { $pb.Image.Dispose() } catch {}
Remove-Item $tmpImg   -Force -ErrorAction SilentlyContinue
Remove-Item $tmpSound -Force -ErrorAction SilentlyContinue
Log "Done"