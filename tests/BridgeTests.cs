using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace AdvancedRPC
{
    internal sealed class FragmentedStream : MemoryStream
    {
        internal FragmentedStream(byte[] bytes) : base(bytes) { }
        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken token)
        {
            return base.ReadAsync(buffer, offset, Math.Min(3, count), token);
        }
    }
    internal static class BridgeTests
    {
        private static void Check(bool value) { if (!value) throw new Exception("Bridge assertion failed."); }
        private static void Reject(Action action)
        {
            try { action(); }
            catch (InvalidDataException) { return; }
            throw new Exception("Invalid input was accepted.");
        }
        private static async Task Run()
        {
            var hello = new Frame(0, Wire.Json(new { v = 1, client_id = "123456789012345678" }));
            Check(Wire.ApplicationId(hello) == "123456789012345678");
            Reject(() => Wire.ApplicationId(new Frame(1, hello.Body)));
            Reject(() => Wire.ApplicationId(new Frame(0, Wire.Json(new { v = 1, client_id = "invalid" }))));
            var activity = new { details = "Driving", assets = new { large_image = "https://example.com/map.png", large_text = "Карта: Italy", small_image = "https://example.com/car.gif", small_text = "Car" } };
            var outgoing = new Frame(1, Wire.Json(new { cmd = "SET_ACTIVITY", nonce = "n1", args = new { pid = 0, activity = activity } }));
            var forwarded = Wire.Parse(Wire.Activity(outgoing, 1234).Body);
            var args = Wire.Get(forwarded, "args") as System.Collections.Generic.Dictionary<string, object>;
            Check(Equals(Wire.Get(args, "pid"), 1234));
            Check(Wire.Utf8.GetString(Wire.Json(Wire.Get(args, "activity"))) == Wire.Utf8.GetString(Wire.Json(activity)));
            Reject(() => Wire.Activity(new Frame(1, Wire.Json(new { cmd = "GET_CHANNELS", nonce = "x", args = new { } })), 1234));
            var stream = new MemoryStream();
            await Wire.Write(stream, outgoing, new SemaphoreSlim(1), CancellationToken.None);
            var decoded = await Wire.Read(new FragmentedStream(stream.ToArray()), 1000, CancellationToken.None);
            Check(decoded.Opcode == outgoing.Opcode && Wire.Utf8.GetString(decoded.Body) == Wire.Utf8.GetString(outgoing.Body));
            byte[] oversized = new byte[8];
            Buffer.BlockCopy(BitConverter.GetBytes(65537), 0, oversized, 4, 4);
            bool rejected = false;
            try { await Wire.Read(new MemoryStream(oversized), 1000, CancellationToken.None); }
            catch (InvalidDataException) { rejected = true; }
            Check(rejected);
            rejected = false;
            try { await Wire.Read(new MemoryStream(new byte[3]), 1000, CancellationToken.None); }
            catch (EndOfStreamException) { rejected = true; }
            Check(rejected);
            Console.WriteLine("PASS bridge framing, partial reads, bounds, handshake, command restriction, PID, URLs and Unicode captions");
            string testKey = @"Software\AdvancedRPC_StartupTest_" + Guid.NewGuid().ToString("N");
            string executable = @"C:\RPC folder\Мост\AdvancedRPC Bridge.exe";
            var startup = new StartupRegistration(testKey, "Test bridge");
            try
            {
                Check(!startup.IsEnabled(executable));
                startup.SetEnabled(true, executable);
                Check(startup.IsEnabled(executable));
                using (var key = Registry.CurrentUser.OpenSubKey(testKey))
                    Check((string)key.GetValue("Test bridge") == "\"" + executable + "\" --autostart");
                Check(!startup.IsEnabled(@"C:\Moved\AdvancedRPC Bridge.exe"));
                startup.SetEnabled(false, executable);
                startup.MigrateLegacy("CustomRPC Bridge", executable);
                Check(!startup.IsEnabled(executable));
                using (var key = Registry.CurrentUser.OpenSubKey(testKey, true))
                    key.SetValue("CustomRPC Bridge", StartupRegistration.Command(@"C:\Old\CustomRPC Bridge.exe"));
                startup.MigrateLegacy("CustomRPC Bridge", executable);
                Check(startup.IsEnabled(executable));
                using (var key = Registry.CurrentUser.OpenSubKey(testKey))
                    Check(key.GetValue("CustomRPC Bridge") == null);
                string moved = @"C:\Moved\AdvancedRPC Bridge.exe";
                startup.SetEnabled(true, moved);
                using (var key = Registry.CurrentUser.OpenSubKey(testKey, true))
                    key.SetValue("CustomRPC Bridge", StartupRegistration.Command(@"C:\Old\CustomRPC Bridge.exe"));
                startup.MigrateLegacy("CustomRPC Bridge", executable);
                Check(startup.IsEnabled(moved));
                using (var key = Registry.CurrentUser.OpenSubKey(testKey))
                    Check(key.GetValue("CustomRPC Bridge") == null);
                startup.SetEnabled(false, moved);
                Check(!startup.IsEnabled(executable));
                startup.SetEnabled(false, executable);
            }
            finally { Registry.CurrentUser.DeleteSubKeyTree(testKey, false); }
            Console.WriteLine("PASS startup enable, disable, quoting, Unicode, moved-executable detection and legacy migration; Windows startup unchanged");
        }
        public static int Main()
        {
            try { Run().GetAwaiter().GetResult(); return 0; }
            catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        }
    }
}
