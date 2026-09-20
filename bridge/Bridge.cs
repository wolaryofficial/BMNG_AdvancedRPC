using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("AdvancedRPC Bridge")]
[assembly: AssemblyDescription("BeamNG.drive Discord Rich Presence bridge")]
[assembly: AssemblyCompany("wolary (w0kx)")]
[assembly: AssemblyProduct("AdvancedRPC")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace AdvancedRPC
{
    internal sealed class StartupRegistration
    {
        private readonly string keyPath;
        private readonly string valueName;
        internal StartupRegistration(string keyPath, string valueName) { this.keyPath = keyPath; this.valueName = valueName; }
        internal static string Command(string executable)
        {
            if (String.IsNullOrWhiteSpace(executable) || executable.IndexOf('"') >= 0 || !Path.IsPathRooted(executable))
                throw new ArgumentException("Choose an absolute executable path.");
            return "\"" + Path.GetFullPath(executable) + "\" --autostart";
        }
        internal bool IsEnabled(string executable)
        {
            using (var key = Registry.CurrentUser.OpenSubKey(keyPath))
                return key != null && String.Equals(key.GetValue(valueName) as string, Command(executable), StringComparison.OrdinalIgnoreCase);
        }
        internal void SetEnabled(bool enabled, string executable)
        {
            using (var key = Registry.CurrentUser.CreateSubKey(keyPath))
            {
                if (key == null) throw new IOException("Windows startup settings are unavailable.");
                if (enabled) key.SetValue(valueName, Command(executable), RegistryValueKind.String);
                else key.DeleteValue(valueName, false);
            }
        }
        internal void MigrateLegacy(string legacyName, string executable)
        {
            using (var key = Registry.CurrentUser.OpenSubKey(keyPath, true))
            {
                if (key == null || !(key.GetValue(legacyName) is string)) return;
                if (key.GetValue(valueName) == null) key.SetValue(valueName, Command(executable), RegistryValueKind.String);
                key.DeleteValue(legacyName, false);
            }
        }
    }

    internal sealed class Frame
    {
        internal int Opcode;
        internal byte[] Body;
        internal Frame(int opcode, byte[] body) { Opcode = opcode; Body = body; }
    }

    internal static class Wire
    {
        internal static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);
        internal static byte[] Json(object value) { return Utf8.GetBytes(new JavaScriptSerializer().Serialize(value)); }
        internal static Dictionary<string, object> Parse(byte[] bytes)
        {
            var json = new JavaScriptSerializer { MaxJsonLength = 65536, RecursionLimit = 32 };
            var value = json.DeserializeObject(Utf8.GetString(bytes)) as Dictionary<string, object>;
            if (value == null) throw new InvalidDataException("Expected a JSON object.");
            return value;
        }
        internal static object Get(Dictionary<string, object> value, string key)
        {
            object result;
            return value != null && value.TryGetValue(key, out result) ? result : null;
        }
        private static async Task ReadExact(Stream stream, byte[] bytes, CancellationToken token)
        {
            int offset = 0;
            while (offset < bytes.Length)
            {
                int count = await stream.ReadAsync(bytes, offset, bytes.Length - offset, token).ConfigureAwait(false);
                if (count == 0) throw new EndOfStreamException("Connection closed.");
                offset += count;
            }
        }
        internal static async Task<Frame> Read(Stream stream, int timeout, CancellationToken token)
        {
            using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(token))
            {
                if (timeout > 0) deadline.CancelAfter(timeout);
                using (deadline.Token.Register(() => stream.Dispose()))
                {
                    var header = new byte[8];
                    await ReadExact(stream, header, deadline.Token).ConfigureAwait(false);
                    int opcode = BitConverter.ToInt32(header, 0), length = BitConverter.ToInt32(header, 4);
                    if (length < 0 || length > 65536) throw new InvalidDataException("IPC frame exceeds its limit.");
                    var body = new byte[length];
                    await ReadExact(stream, body, deadline.Token).ConfigureAwait(false);
                    return new Frame(opcode, body);
                }
            }
        }
        internal static async Task Write(Stream stream, Frame frame, SemaphoreSlim gate, CancellationToken token)
        {
            await gate.WaitAsync(token).ConfigureAwait(false);
            try
            {
                var bytes = new byte[frame.Body.Length + 8];
                Buffer.BlockCopy(BitConverter.GetBytes(frame.Opcode), 0, bytes, 0, 4);
                Buffer.BlockCopy(BitConverter.GetBytes(frame.Body.Length), 0, bytes, 4, 4);
                Buffer.BlockCopy(frame.Body, 0, bytes, 8, frame.Body.Length);
                await stream.WriteAsync(bytes, 0, bytes.Length, token).ConfigureAwait(false);
            }
            finally { gate.Release(); }
        }
        internal static Frame Activity(Frame frame, int processId)
        {
            if (frame.Opcode != 1) throw new InvalidDataException("Unsupported bridge command.");
            var data = Parse(frame.Body);
            var args = Get(data, "args") as Dictionary<string, object>;
            var nonce = Get(data, "nonce") as string;
            if (Get(data, "cmd") as string != "SET_ACTIVITY" || args == null || nonce == null || nonce.Length > 128 || !args.ContainsKey("activity"))
                throw new InvalidDataException("Only Rich Presence updates are accepted.");
            var activity = Get(args, "activity");
            if (activity != null && !(activity is Dictionary<string, object>)) throw new InvalidDataException("Invalid activity.");
            return new Frame(1, Json(new { cmd = "SET_ACTIVITY", nonce = nonce, args = new { pid = processId, activity = activity } }));
        }
        internal static string ApplicationId(Frame frame)
        {
            if (frame.Opcode != 0) throw new InvalidDataException("Expected a Discord handshake.");
            var data = Parse(frame.Body);
            var id = Get(data, "client_id") as string;
            if (!Equals(Get(data, "v"), 1) || id == null || !Regex.IsMatch(id, "^[0-9]{17,20}$")) throw new InvalidDataException("Invalid Discord Application ID.");
            return id;
        }
    }

    internal sealed class Session : IDisposable
    {
        private readonly TcpClient client;
        private readonly Action<string> status;
        private readonly CancellationTokenSource stop = new CancellationTokenSource();
        private readonly SemaphoreSlim networkGate = new SemaphoreSlim(1, 1), pipeGate = new SemaphoreSlim(1, 1);
        private NamedPipeClientStream pipe;
        private NetworkStream network;
        internal Session(TcpClient client, Action<string> status) { this.client = client; this.status = status; }
        internal async Task Run()
        {
            try
            {
                client.NoDelay = true;
                network = client.GetStream();
                string id = Wire.ApplicationId(await Wire.Read(network, 10000, stop.Token).ConfigureAwait(false));
                status("Connecting to Discord");
                for (int index = 0; index < 10; index++)
                {
                    var candidate = new NamedPipeClientStream(".", "discord-ipc-" + index, PipeDirection.InOut, PipeOptions.Asynchronous);
                    try { await candidate.ConnectAsync(150, stop.Token).ConfigureAwait(false); pipe = candidate; break; }
                    catch (TimeoutException) { candidate.Dispose(); }
                    catch (IOException) { candidate.Dispose(); }
                    catch (UnauthorizedAccessException) { candidate.Dispose(); }
                    catch (OperationCanceledException) { candidate.Dispose(); throw; }
                }
                if (pipe == null)
                {
                    await Wire.Write(network, new Frame(2, Wire.Json(new { message = "Discord desktop not detected. Start Discord and keep it running." })), networkGate, stop.Token).ConfigureAwait(false);
                    status("Start the Discord desktop app");
                    return;
                }
                await Wire.Write(pipe, new Frame(0, Wire.Json(new { v = 1, client_id = id })), pipeGate, stop.Token).ConfigureAwait(false);
                Task outgoing = FromGame(), incoming = FromDiscord();
                await Task.WhenAny(outgoing, incoming).ConfigureAwait(false);
                Dispose();
                try { await Task.WhenAll(outgoing, incoming).ConfigureAwait(false); }
                catch (Exception) { }
                status("Waiting for BeamNG");
            }
            catch (Exception error)
            {
                if (!stop.IsCancellationRequested) status(error is EndOfStreamException ? "Waiting for BeamNG" : "Connection closed: " + error.Message);
            }
            finally { Dispose(); }
        }
        private async Task FromGame()
        {
            int processId = Process.GetCurrentProcess().Id;
            while (!stop.IsCancellationRequested)
            {
                var frame = await Wire.Read(network, 20000, stop.Token).ConfigureAwait(false);
                if (frame.Opcode == 3)
                    await Wire.Write(network, new Frame(4, frame.Body), networkGate, stop.Token).ConfigureAwait(false);
                else if (frame.Opcode == 4)
                    await Wire.Write(pipe, frame, pipeGate, stop.Token).ConfigureAwait(false);
                else
                    await Wire.Write(pipe, Wire.Activity(frame, processId), pipeGate, stop.Token).ConfigureAwait(false);
            }
        }
        private async Task FromDiscord()
        {
            while (!stop.IsCancellationRequested)
            {
                var frame = await Wire.Read(pipe, 0, stop.Token).ConfigureAwait(false);
                if (frame.Opcode == 1)
                {
                    var data = Wire.Parse(frame.Body);
                    if (Wire.Get(data, "evt") as string == "READY")
                    {
                        frame = new Frame(1, Wire.Json(new { cmd = "DISPATCH", evt = "READY" }));
                        status("Connected to Discord");
                    }
                    else if (Wire.Get(data, "evt") as string == "ERROR") status("Discord rejected the activity; see in-game settings");
                    else if (Wire.Get(data, "cmd") as string == "SET_ACTIVITY") status("Activity accepted by Discord");
                }
                await Wire.Write(network, frame, networkGate, stop.Token).ConfigureAwait(false);
            }
        }
        public void Dispose()
        {
            if (!stop.IsCancellationRequested) stop.Cancel();
            client.Close();
            if (pipe != null) pipe.Dispose();
        }
    }

    internal sealed class Tray : ApplicationContext
    {
        private readonly NotifyIcon icon;
        private readonly Icon artwork;
        private readonly System.Windows.Forms.Timer timer;
        private readonly StartupRegistration startup = new StartupRegistration(@"Software\Microsoft\Windows\CurrentVersion\Run", "AdvancedRPC Bridge");
        private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 29734);
        private Session current;
        private volatile string status = "Waiting for BeamNG";
        private volatile bool stopping;
        internal Tray()
        {
            listener.Server.ExclusiveAddressUse = true;
            listener.Start(1);
            var menu = new ContextMenuStrip();
            menu.Items.Add("Show status", null, (sender, args) => ShowStatus());
            var startupItem = new ToolStripMenuItem("Start with Windows");
            try { startup.MigrateLegacy("CustomRPC Bridge", Application.ExecutablePath); }
            catch (Exception error) { status = "Startup update failed: " + error.Message; }
            startupItem.Click += (sender, args) =>
            {
                try
                {
                    startup.SetEnabled(!startup.IsEnabled(Application.ExecutablePath), Application.ExecutablePath);
                    startupItem.Checked = startup.IsEnabled(Application.ExecutablePath);
                }
                catch (Exception error) { MessageBox.Show(error.Message, "AdvancedRPC startup", MessageBoxButtons.OK, MessageBoxIcon.Error); }
            };
            menu.Items.Add(startupItem);
            menu.Opening += (sender, args) =>
            {
                try { startupItem.Checked = startup.IsEnabled(Application.ExecutablePath); startupItem.Enabled = true; }
                catch (Exception) { startupItem.Enabled = false; }
            };
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, (sender, args) => ExitThread());
            artwork = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? (Icon)SystemIcons.Application.Clone();
            icon = new NotifyIcon { Icon = artwork, Text = "AdvancedRPC 1.0.0", ContextMenuStrip = menu, Visible = true };
            icon.DoubleClick += (sender, args) => ShowStatus();
            timer = new System.Windows.Forms.Timer { Interval = 1000 };
            timer.Tick += (sender, args) => { string text = "AdvancedRPC: " + status; icon.Text = text.Substring(0, Math.Min(63, text.Length)); };
            timer.Start();
            Task.Run((Func<Task>)Accept);
        }
        private void ShowStatus()
        {
            icon.ShowBalloonTip(5000, "AdvancedRPC 1.0.0", status + ".\nSettings: BeamNG → Esc → Mods → AdvancedRPC\nmade by wolary (w0kx)", ToolTipIcon.Info);
        }
        private async Task Accept()
        {
            while (!stopping)
            {
                bool retry = false;
                try
                {
                    var client = await listener.AcceptTcpClientAsync().ConfigureAwait(false);
                    if (stopping) { client.Close(); return; }
                    if (current != null) { client.Close(); continue; }
                    var session = new Session(client, value => status = value);
                    current = session;
                    RunSession(session);
                }
                catch (Exception error) { if (!stopping) { status = error.Message; retry = true; } }
                if (retry) await Task.Delay(1000).ConfigureAwait(false);
            }
        }
        private async void RunSession(Session session)
        {
            await session.Run().ConfigureAwait(false);
            Interlocked.CompareExchange(ref current, null, session);
        }
        protected override void ExitThreadCore()
        {
            stopping = true;
            listener.Stop();
            var session = current;
            if (session != null) session.Dispose();
            timer.Stop();
            timer.Dispose();
            icon.Visible = false;
            icon.ContextMenuStrip.Dispose();
            icon.Dispose();
            artwork.Dispose();
            base.ExitThreadCore();
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main()
        {
            bool first;
            using (var legacyMutex = new Mutex(true, "Local\\CustomRPC-Bridge-1", out first))
            {
                if (!first) return 0;
                using (var mutex = new Mutex(true, "Local\\AdvancedRPC-Bridge-1", out first))
                {
                    if (!first) return 0;
                    try { Application.EnableVisualStyles(); Application.Run(new Tray()); return 0; }
                    catch (Exception error) { MessageBox.Show(error.Message, "AdvancedRPC Bridge", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
                }
            }
        }
    }
}
