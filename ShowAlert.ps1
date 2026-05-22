# ==============================================================
#  ShowAlert.ps1  –  SELF-CONTAINED, no extra files needed
# ==============================================================
#
#  HOW TO CUSTOMISE
#  ----------------
#  1. Get Base64 of YOUR image (JPG/PNG/BMP):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\image.jpg"))
#     Copy the output and paste it as the value of $IMAGE_B64 below.
#
#  2. Get Base64 of YOUR sound (MP3):
#       [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\sound.mp3"))
#     Copy the output and paste it as the value of $SOUND_B64 below.
#
#  3. Run:
#       powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ShowAlert.ps1
#
# ==============================================================

$DelaySeconds   = 30
$DisplaySeconds = 30
$ImageExt       = "bmp"   # change to jpg or png if needed

# ── EMBEDDED IMAGE (Base64) ────────────────────────────────────
$IMAGE_B64 = ''

# ── EMBEDDED SOUND (Base64 MP3) ───────────────────────────────
$SOUND_B64 = ''

# ==============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ── Win32 ─────────────────────────────────────────────────────
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeHelper {
    // Cursor lock
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(ref RECT r);
    [DllImport("user32.dll")]
    public static extern bool ClipCursor(IntPtr r);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    // Console hide
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    // Force foreground
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr p);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    // Force window to front even when another app owns foreground
    public static void ForceToFront(IntPtr hwnd) {
        IntPtr fg = GetForegroundWindow();
        uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
        uint myThread = GetCurrentThreadId();
        AttachThreadInput(fgThread, myThread, true);
        SetForegroundWindow(hwnd);
        BringWindowToTop(hwnd);
        // HWND_TOPMOST = -1, SWP_NOMOVE|SWP_NOSIZE = 0x0003
        SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0003);
        AttachThreadInput(fgThread, myThread, false);
    }
}
"@

# ── Hide console ──────────────────────────────────────────────
$cw = [NativeHelper]::GetConsoleWindow()
if ($cw -ne [IntPtr]::Zero) { [NativeHelper]::ShowWindow($cw, 0) | Out-Null }

# ── Decode files ──────────────────────────────────────────────
$tmpImg   = "$env:TEMP\alert_img.$ImageExt"
$tmpSound = "$env:TEMP\alert_snd.mp3"

[IO.File]::WriteAllBytes($tmpImg,   [Convert]::FromBase64String($IMAGE_B64))
[IO.File]::WriteAllBytes($tmpSound, [Convert]::FromBase64String($SOUND_B64))

# ── Wait ──────────────────────────────────────────────────────
Start-Sleep -Seconds $DelaySeconds

# ── Start MP3 via WMP COM ─────────────────────────────────────
$wmp = New-Object -ComObject WMPlayer.OCX
$wmp.URL = $tmpSound
$wmp.settings.volume = 100
$wmp.settings.setMode("loop", $true)
$wmp.controls.play()

# ── Build fullscreen form ─────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text            = ""
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.WindowState     = [System.Windows.Forms.FormWindowState]::Maximized
$form.TopMost         = $true
$form.BackColor       = [System.Drawing.Color]::Black
$form.Cursor          = [System.Windows.Forms.Cursors]::None
$form.ShowInTaskbar   = $false

$pb          = New-Object System.Windows.Forms.PictureBox
$pb.Dock     = [System.Windows.Forms.DockStyle]::Fill
$pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$pb.Image    = [System.Drawing.Image]::FromFile($tmpImg)
$form.Controls.Add($pb)

# ── On shown: lock mouse + force to front immediately ─────────
$form.Add_Shown({
    # Lock mouse
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $rect   = New-Object NativeHelper+RECT
    $rect.Left   = $bounds.Left
    $rect.Top    = $bounds.Top
    $rect.Right  = $bounds.Right
    $rect.Bottom = $bounds.Bottom
    [NativeHelper]::ClipCursor([ref]$rect) | Out-Null

    # Force to front
    [NativeHelper]::ForceToFront($form.Handle) | Out-Null
    $form.Activate()
})

# ── Aggressively stay on top every 100ms ─────────────────────
$topTimer          = New-Object System.Windows.Forms.Timer
$topTimer.Interval = 100
$topTimer.Add_Tick({
    if ($form.Handle -ne [IntPtr]::Zero) {
        [NativeHelper]::ForceToFront($form.Handle) | Out-Null
        $form.Activate()
    }
})
$topTimer.Start()

# ── Block keypresses ──────────────────────────────────────────
$form.KeyPreview = $true
$form.Add_KeyDown({
    $_.SuppressKeyPress = $true
    $_.Handled = $true
})

# ── Prevent manual close ──────────────────────────────────────
$script:allowClose = $false
$form.Add_FormClosing({
    if (-not $script:allowClose) { $_.Cancel = $true }
})

# ── Auto-close after DisplaySeconds ──────────────────────────
$closeTimer          = New-Object System.Windows.Forms.Timer
$closeTimer.Interval = $DisplaySeconds * 1000
$closeTimer.Add_Tick({
    $closeTimer.Stop()
    $topTimer.Stop()
    $script:allowClose = $true
    $form.Close()
})
$closeTimer.Start()

# ── Run ───────────────────────────────────────────────────────
[System.Windows.Forms.Application]::Run($form)

# ── Cleanup ───────────────────────────────────────────────────
$wmp.controls.stop()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wmp) | Out-Null
[NativeHelper]::ClipCursor([System.IntPtr]::Zero) | Out-Null
try { $pb.Image.Dispose() } catch {}
Remove-Item $tmpImg   -Force -ErrorAction SilentlyContinue
Remove-Item $tmpSound -Force -ErrorAction SilentlyContinue