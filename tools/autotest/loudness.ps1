# loudness.ps1 : how loud the PC's sound output is, every 100 ms, for the autotest's sound line-ups (2026-11-24).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/autotest/loudness.ps1 -Seconds 300 -Out <file>
# WASAPI loopback on the default playback device (what the speakers get: the game and anything else playing). Only
# levels are written ("HH:mm:ss.fff <dBFS>", -120 for silence), never the sound itself. The autotest's lines carry the
# same clock, so a step's sound is found by its time.
param([int]$Seconds = 300, [string]$Out = "loudness.txt")
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public static class Loud {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCo {}
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int mask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice dev);
    }
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioClient {
        int Initialize(int shareMode, int flags, long bufferDuration, long period, IntPtr format, IntPtr session);
        int GetBufferSize(out uint frames);
        int GetStreamLatency(out long latency);
        int GetCurrentPadding(out uint padding);
        int IsFormatSupported(int mode, IntPtr format, out IntPtr closest);
        int GetMixFormat(out IntPtr format);
        int GetDevicePeriod(out long def, out long min);
        int Start();
        int Stop();
        int Reset();
        int SetEventHandle(IntPtr h);
        int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object o);
    }
    [Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioCaptureClient {
        int GetBuffer(out IntPtr data, out uint frames, out uint flags, out long pos, out long qpc);
        int ReleaseBuffer(uint frames);
        int GetNextPacketSize(out uint frames);
    }
    static void Ok(int hr, string what) { if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("x8")); }
    public static string Run(int seconds, string outPath) {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCo();
        IMMDevice dev; Ok(en.GetDefaultAudioEndpoint(0, 0, out dev), "GetDefaultAudioEndpoint");
        Guid iidClient = typeof(IAudioClient).GUID; object o;
        Ok(dev.Activate(ref iidClient, 23, IntPtr.Zero, out o), "Activate");
        var client = (IAudioClient)o;
        IntPtr fmt; Ok(client.GetMixFormat(out fmt), "GetMixFormat");
        int tag = Marshal.ReadInt16(fmt, 0), ch = Marshal.ReadInt16(fmt, 2), rate = Marshal.ReadInt32(fmt, 4), bits = Marshal.ReadInt16(fmt, 14);
        bool isFloat = bits == 32 && (tag == 3 || tag == unchecked((short)0xFFFE));
        Ok(client.Initialize(0, 0x00020000, 10000000, 0, fmt, IntPtr.Zero), "Initialize (loopback)");
        Guid iidCap = typeof(IAudioCaptureClient).GUID;
        Ok(client.GetService(ref iidCap, out o), "GetService");
        var cap = (IAudioCaptureClient)o;
        Ok(client.Start(), "Start");
        var w = new StreamWriter(outPath, false);
        w.WriteLine("# loudness.ps1: " + rate + " Hz, " + ch + " ch, " + bits + " bit" + (isFloat ? " float" : " int") + "; dBFS every 100 ms");
        var end = DateTime.Now.AddSeconds(seconds);
        var winEnd = DateTime.Now.AddMilliseconds(100);
        double sum = 0; long n = 0;
        while (DateTime.Now < end) {
            Thread.Sleep(10);
            uint pkt;
            while (cap.GetNextPacketSize(out pkt) >= 0 && pkt > 0) {
                IntPtr data; uint frames, flags; long pos, qpc;
                if (cap.GetBuffer(out data, out frames, out flags, out pos, out qpc) < 0) break;
                int count = (int)frames * ch;
                if ((flags & 2) == 0 && count > 0) {
                    if (isFloat) {
                        var buf = new float[count]; Marshal.Copy(data, buf, 0, count);
                        for (int i = 0; i < count; i++) sum += (double)buf[i] * buf[i];
                    } else if (bits == 16) {
                        var buf = new short[count]; Marshal.Copy(data, buf, 0, count);
                        for (int i = 0; i < count; i++) { double v = buf[i] / 32768.0; sum += v * v; }
                    }
                }
                n += count;
                cap.ReleaseBuffer(frames);
            }
            if (DateTime.Now >= winEnd) {
                double db = (n > 0 && sum > 0) ? 10 * Math.Log10(sum / n) : -120;
                w.WriteLine(winEnd.ToString("HH:mm:ss.fff") + " " + Math.Max(-120, db).ToString("0.0"));
                sum = 0; n = 0; winEnd = winEnd.AddMilliseconds(100);
            }
        }
        client.Stop(); w.Close();
        return rate + " Hz, " + ch + " ch, " + bits + " bit";
    }
}
"@
$r = [Loud]::Run($Seconds, $Out)
Write-Output "loudness: $r, $Seconds s -> $Out"
