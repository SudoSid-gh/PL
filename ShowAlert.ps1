# ==============================================================
#  ShowAlert.ps1  –  SELF-CONTAINED, no extra files needed
# ==============================================================
#
#  HOW TO CUSTOMISE
#  ----------------
#  1. Get Base64 of YOUR image (JPG/PNG/BMP):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\image.jpg"))
#
#  2. Get Base64 of YOUR sound (WAV/MP3):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\sound.wav"))
#
#  3. Run (hidden window, detached from terminal):
#       powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File ShowAlert.ps1
#
# ==============================================================

# ── SETTINGS ──────────────────────────────────────────────────
$DelaySeconds   = 30    # seconds to wait before showing
$DisplaySeconds = 30    # seconds to show image/play sound
$ImageExt       = "bmp" # extension that matches your embedded image (jpg/png/bmp)
$SoundExt       = "mp3" # wav recommended; mp3 needs Windows Media Player

# ── EMBEDDED IMAGE (Base64) ────────────────────────────────────
$IMAGE_B64 = ''

# ── EMBEDDED SOUND (Base64 WAV) ───────────────────────────────
$SOUND_B64 = ''

# ==============================================================
#  Everything below this line runs automatically
# ==============================================================

# ── Detach from terminal so closing it won't kill this process ─
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [DllImport("kernel32.dll")]
    public static extern bool FreeConsole();
}
"@
[ConsoleHelper]::FreeConsole() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName presentationCore  # for MediaPlayer (MP3 support)

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

# ── 1. Decode embedded files to TEMP ──────────────────────────
$tmpImg   = [IO.Path]::Combine([IO.Path]::GetTempPath(), "alert_img.$ImageExt")
$tmpSound = [IO.Path]::Combine([IO.Path]::GetTempPath(), "alert_snd.$SoundExt")

[IO.File]::WriteAllBytes($tmpImg,   [Convert]::FromBase64String($IMAGE_B64))
[IO.File]::WriteAllBytes($tmpSound, [Convert]::FromBase64String($SOUND_B64))

# ── 2. Wait ────────────────────────────────────────────────────
Start-Sleep -Seconds $DelaySeconds

# ── 3. Build fullscreen form ───────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = ""
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.WindowState     = [System.Windows.Forms.FormWindowState]::Maximized
$form.TopMost         = $true
$form.BackColor       = [System.Drawing.Color]::Black
$form.Cursor          = [System.Windows.Forms.Cursors]::None

$pb           = New-Object System.Windows.Forms.PictureBox
$pb.Dock      = [System.Windows.Forms.DockStyle]::Fill
$pb.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$pb.Image     = [System.Drawing.Image]::FromFile($tmpImg)
$form.Controls.Add($pb)

# ── 4. Play sound looping via MediaPlayer (supports WAV + MP3) ─
$mediaPlayer = New-Object System.Windows.Media.MediaPlayer
$mediaPlayer.Open([Uri]::new($tmpSound))
$mediaPlayer.Volume = 1.0

# Loop by restarting on end
$mediaPlayer.Add_MediaEnded({
    $mediaPlayer.Position = [TimeSpan]::Zero
    $mediaPlayer.Play()
})

$form.Add_Shown({
    $mediaPlayer.Play()
})

# ── 5. Lock mouse to primary screen ───────────────────────────
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$rect   = New-Object Win32Cursor+RECT
$rect.Left=$bounds.Left; $rect.Top=$bounds.Top
$rect.Right=$bounds.Right; $rect.Bottom=$bounds.Bottom
[Win32Cursor]::ClipCursor([ref]$rect) | Out-Null

# ── 6. Block ALL keyboard input including Alt+F4, Win key ─────
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;
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
        if (nCode >= 0) return (IntPtr)1; // block all keys
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }
}
"@
[KeyboardBlocker]::Install()

# ── 7. Prevent manual close ───────────────────────────────────
$script:allowClose = $false

$form.Add_FormClosing({
    if (-not $script:allowClose) {
        $_.Cancel = $true
    }
})

# ── 8. Auto-close timer ($DisplaySeconds) ─────────────────────
$timer          = New-Object System.Windows.Forms.Timer
$timer.Interval = $DisplaySeconds * 1000
$timer.Add_Tick({
    $timer.Stop()
    $script:allowClose = $true
    $form.Close()
})
$timer.Start()

# ── 9. Run (blocks here until timer fires) ────────────────────
[System.Windows.Forms.Application]::Run($form)

# ── 10. Cleanup ───────────────────────────────────────────────
[KeyboardBlocker]::Uninstall()
$mediaPlayer.Stop()
$mediaPlayer.Close()
[Win32Cursor]::ClipCursor([System.IntPtr]::Zero) | Out-Null
$pb.Image.Dispose()
Remove-Item $tmpImg   -Force -ErrorAction SilentlyContinue
Remove-Item $tmpSound -Force -ErrorAction SilentlyContinue