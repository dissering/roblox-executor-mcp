import { execSync } from "child_process";
import fs from "fs";
import os from "os";
import path from "path";

export interface RobloxWindowInfo {
  pid: number;
  hwnd: string;
  title: string;
}

export interface ScreenshotResult {
  error?: string;
  needsDisambiguation?: boolean;
  windows?: RobloxWindowInfo[];
  imageBase64?: string;
  mimeType?: string;
}

export const DEFAULT_SCREENSHOT_MAX_WIDTH = 2560;
export const DEFAULT_SCREENSHOT_JPEG_QUALITY = 90;

export function isSupported(): boolean {
  return process.platform === "win32";
}

export function enumRobloxWindows(): RobloxWindowInfo[] {
  const ps = `
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class WinEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int maxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    public static List<object[]> GetVisibleWindows() {
        var result = new List<object[]>();
        EnumWindows((hWnd, _) => {
            if (!IsWindowVisible(hWnd)) return true;
            var sb = new StringBuilder(256);
            GetWindowText(hWnd, sb, 256);
            string title = sb.ToString();
            if (string.IsNullOrEmpty(title)) return true;
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            result.Add(new object[] { pid, hWnd.ToString(), title });
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
"@

$robloxPids = @(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
if ($robloxPids.Count -eq 0) {
    Write-Output '[]'
    exit
}
$allWindows = [WinEnum]::GetVisibleWindows()
$found = @()
foreach ($w in $allWindows) {
    if ($robloxPids -contains [int]$w[0]) {
        $found += [PSCustomObject]@{ pid=[int]$w[0]; hwnd=$w[1]; title=$w[2] }
    }
}
if ($found.Count -eq 0) {
    Write-Output '[]'
} else {
    $found | ConvertTo-Json -Compress
}
`;

  const tmpFile = path.join(os.tmpdir(), `roblox_enum_${Date.now()}.ps1`);
  try {
    fs.writeFileSync(tmpFile, ps, "utf-8");
    const raw = execSync(
      `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmpFile}"`,
      { encoding: "utf-8", timeout: 15000, windowsHide: true }
    ).trim();
    if (!raw || raw === "" || raw === "null") return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch (err) {
    console.error("[Screenshot] enumRobloxWindows failed:", (err as Error).message);
    return [];
  } finally {
    try { fs.unlinkSync(tmpFile); } catch { /* ignore */ }
  }
}

function captureWindowPNG(
  hwnd: string,
  maxWidth: number = DEFAULT_SCREENSHOT_MAX_WIDTH,
  jpegQuality: number = DEFAULT_SCREENSHOT_JPEG_QUALITY
): string {
  const outFile = path.join(os.tmpdir(), `roblox_screenshot_${Date.now()}.b64`);
  const safeMaxWidth = Math.max(320, Math.min(Math.floor(maxWidth) || DEFAULT_SCREENSHOT_MAX_WIDTH, 3840));
  const safeQuality = Math.max(30, Math.min(Math.floor(jpegQuality) || DEFAULT_SCREENSHOT_JPEG_QUALITY, 95));
  const ps = `
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hDC, uint nFlags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

$hwnd = [IntPtr]::new([long]${hwnd})

if ([WinCapture]::IsIconic($hwnd)) {
    [WinCapture]::ShowWindow($hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 200
}

$rect = New-Object WinCapture+RECT
[WinCapture]::GetClientRect($hwnd, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
if ($w -le 0 -or $h -le 0) {
    Write-Error "Window has zero size"
    exit 1
}

$bmp = New-Object System.Drawing.Bitmap($w, $h)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $gfx.GetHdc()
[WinCapture]::PrintWindow($hwnd, $hdc, 2) | Out-Null
$gfx.ReleaseHdc($hdc)
$gfx.Dispose()

# Downscale to keep vision-token cost low.
$maxWidth = ${safeMaxWidth}
$final = $bmp
if ($w -gt $maxWidth) {
    $ratio = $maxWidth / $w
    $nw = [int]($w * $ratio)
    $nh = [int]($h * $ratio)
    $resized = New-Object System.Drawing.Bitmap($nw, $nh)
    $rg = [System.Drawing.Graphics]::FromImage($resized)
    $rg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $rg.DrawImage($bmp, 0, 0, $nw, $nh)
    $rg.Dispose()
    $bmp.Dispose()
    $final = $resized
}

# Encode as JPEG to shrink payload vs raw PNG.
$jpgCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
$encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]${safeQuality})

$ms = New-Object System.IO.MemoryStream
$final.Save($ms, $jpgCodec, $encParams)
$final.Dispose()
$bytes = $ms.ToArray()
$ms.Dispose()
$b64 = [Convert]::ToBase64String($bytes)
[System.IO.File]::WriteAllText('${outFile.replace(/\\/g, "\\\\")}', $b64)
Write-Output 'OK'
`;

  const tmpFile = path.join(os.tmpdir(), `roblox_capture_${Date.now()}.ps1`);
  try {
    fs.writeFileSync(tmpFile, ps, "utf-8");
    execSync(
      `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmpFile}"`,
      { encoding: "utf-8", timeout: 15000, windowsHide: true }
    );

    if (!fs.existsSync(outFile)) throw new Error("PrintWindow did not produce output file");
    const result = fs.readFileSync(outFile, "utf-8").trim();
    if (!result) throw new Error("PrintWindow returned empty output");
    return result;
  } finally {
    try { fs.unlinkSync(tmpFile); } catch { /* ignore */ }
    try { fs.unlinkSync(outFile); } catch { /* ignore */ }
  }
}

export function performScreenshot(pid?: number, maxWidth?: number): ScreenshotResult {
  const windows = enumRobloxWindows();

  if (windows.length === 0) {
    return { error: "No visible Roblox windows found. Make sure Roblox is running and not minimized." };
  }

  let targets = windows;
  if (pid !== undefined) {
    targets = windows.filter((w) => w.pid === pid);
    if (targets.length === 0) {
      return {
        error: `No Roblox window found for PID ${pid}. Available windows:\n` +
          windows.map((w) => `  PID ${w.pid} — "${w.title}"`).join("\n"),
      };
    }
  }

  if (targets.length > 1 && pid === undefined) {
    return {
      needsDisambiguation: true,
      windows: targets,
    };
  }

  const target = targets[0]!;
  const imageBase64 = captureWindowPNG(target.hwnd, maxWidth);
  return { imageBase64, mimeType: "image/jpeg" };
}
