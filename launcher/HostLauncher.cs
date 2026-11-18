using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using System.Threading;
using System.Security.Cryptography;

// Local, offline host utility. No registry/environment changes, downloads, uploads or real-save access.
// Build with the existing Windows .NET Framework C# compiler. See BUILD_LAUNCHER.txt.
class HostLauncher : Form {
    const string AppName = "Kuro_sukobann_menuwarm";
    readonly string project = AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    string privateRoot, sessionsRoot;
    TextBox engine = new TextBox(), status = new TextBox();
    ComboBox sessions = new ComboBox();
    Button browse = new Button(), fresh = new Button(), resume = new Button();
    CheckBox reveal = new CheckBox();
    Label preview = new Label();
    bool busy;

    [STAThread] static void Main() {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new HostLauncher());
    }
    public HostLauncher() {
        Text = "推箱工坊 · 盲测主持人启动器";
        Font = new Font("Microsoft YaHei UI", 10);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(900, 570);
        MinimumSize = new Size(850, 580);
        StartPosition = FormStartPosition.CenterScreen;
        privateRoot = Path.Combine(project, ".host-private");
        sessionsRoot = Path.Combine(privateRoot, "Sessions");
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(20), ColumnCount = 1, RowCount = 10 };
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 65));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 48));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        layout.Controls.Add(new Label { Text = "主持人选择已有 Godot 4.6.x 标准版 EXE（本工具不下载安装）", AutoSize = true }, 0, 0);
        var pathRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        pathRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 170));
        engine.Dock = DockStyle.Fill;
        engine.AccessibleName = "Godot EXE 完整路径";
        engine.UseSystemPasswordChar = true;
        browse.Text = "选择 Godot EXE…"; browse.Dock = DockStyle.Fill;
        browse.Click += delegate { using (var d = new OpenFileDialog()) {
            d.Title = "选择已安装的 Godot 4.6.x EXE";
            d.Filter = "Godot / Windows EXE (*.exe)|*.exe";
            d.CheckFileExists = true;
            if (d.ShowDialog(this) == DialogResult.OK) engine.Text = d.FileName;
        }};
        pathRow.Controls.Add(engine, 0, 0); pathRow.Controls.Add(browse, 1, 0); layout.Controls.Add(pathRow, 0, 1);
        reveal.Text = "显示本机完整路径（截图和分享前请关闭）"; reveal.AutoSize = true;
        reveal.CheckedChanged += delegate { engine.UseSystemPasswordChar = !reveal.Checked; UpdatePreview(); };
        layout.Controls.Add(reveal, 0, 2);
        layout.Controls.Add(new Label { Text = "每位首次玩家点“新测试者”；同一人继续时选择会话再点“继续”。", AutoSize = true }, 0, 3);
        sessions.Dock = DockStyle.Fill; sessions.DropDownStyle = ComboBoxStyle.DropDownList;
        sessions.AccessibleName = "隔离会话"; sessions.SelectedIndexChanged += delegate { UpdatePreview(); };
        layout.Controls.Add(sessions, 0, 4);
        preview.Dock = DockStyle.Fill; preview.AutoEllipsis = true;
        layout.Controls.Add(preview, 0, 5);
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill };
        fresh.Text = "新测试者（空白）"; fresh.Width = 230; fresh.Height = 40;
        resume.Text = "继续选中测试"; resume.Width = 230; resume.Height = 40;
        fresh.Click += delegate { BeginSession(true); }; resume.Click += delegate { BeginSession(false); };
        buttons.Controls.Add(fresh); buttons.Controls.Add(resume); layout.Controls.Add(buttons, 0, 6);
        status.Multiline = true; status.ReadOnly = true; status.ScrollBars = ScrollBars.Vertical; status.Dock = DockStyle.Fill;
        status.AccessibleName = "启动与退出状态";
        status.Text = "尚未启动。请选择或输入 Godot 路径。\r\n只使用本副本 .host-private 中的数据；不读取、重置或删除真实存档。";
        layout.Controls.Add(status, 0, 7);
        layout.Controls.Add(new Label { Text = "遇到 Windows 安全警告请停止；本工具不绕过策略、不自动上传。", AutoSize = true }, 0, 8);
        Controls.Add(layout);
        Load += delegate { try {
            var p = Path.Combine(privateRoot, "engine-path.txt");
            if (File.Exists(p)) engine.Text = File.ReadAllText(p, Encoding.UTF8);
            RefreshSessions(null);
        } catch (Exception e) { SetStatus("读取本副本主持人配置失败：" + SafeMessage(e.Message)); } };
        FormClosing += delegate(object sender, FormClosingEventArgs e) {
            if (busy) { e.Cancel = true; MessageBox.Show(this, "请先从游戏正常退出，再关闭主持人窗口。", "游戏仍在运行"); }
        };
    }
    string SafeMessage(string s) { return s.Replace(project, "[当前副本]").Replace(project.Replace('\\','/'), "[当前副本]"); }
    void SetStatus(string text) {
        if (IsDisposed) return;
        if (InvokeRequired) { BeginInvoke(new Action<string>(SetStatus), text); return; }
        status.Text = SafeMessage(text);
    }
    void RefreshSessions(string wanted) {
        sessions.Items.Clear();
        if (Directory.Exists(sessionsRoot)) foreach (var p in Directory.GetDirectories(sessionsRoot)) {
            if ((File.GetAttributes(p) & FileAttributes.ReparsePoint) == 0 && File.Exists(Path.Combine(p, "host-session.marker"))) sessions.Items.Add(Path.GetFileName(p));
        }
        if (wanted != null && sessions.Items.Contains(wanted)) sessions.SelectedItem = wanted;
        else if (sessions.Items.Count > 0) sessions.SelectedIndex = sessions.Items.Count - 1;
        resume.Enabled = !busy && sessions.SelectedItem != null;
        UpdatePreview();
    }
    void UpdatePreview() {
        string id = sessions.SelectedItem as string;
        string suffix = id == null ? "[新会话]" : id;
        string p = Path.Combine(sessionsRoot, suffix, "roaming", "Godot", "app_userdata", AppName);
        preview.Text = "user://：" + (reveal.Checked ? p : ".host-private\\Sessions\\" + suffix + "\\roaming\\Godot\\app_userdata\\" + AppName) + "\r\n完整实际路径与校验结果仅写入本机会话日志。";
    }
    static string Quote(string arg) {
        // Windows CommandLineToArgvW-compatible quoting, including spaces and trailing backslashes.
        return "\"" + Regex.Replace(arg, "(\\\\*)\"", "$1$1\\\"").TrimEnd('\\') + new string('\\', arg.Length - arg.TrimEnd('\\').Length) + new string('\\', arg.Length - arg.TrimEnd('\\').Length) + "\"";
    }
    string Run(string exe, string args, string data, string log, bool visible, out int code) {
        var info = new ProcessStartInfo(exe, args);
        info.UseShellExecute = false;
        info.WorkingDirectory = data;
        info.CreateNoWindow = !visible;
        info.RedirectStandardOutput = true; info.RedirectStandardError = true;
        info.StandardOutputEncoding = Encoding.UTF8; info.StandardErrorEncoding = Encoding.UTF8;
        info.EnvironmentVariables["APPDATA"] = Path.Combine(data, "roaming");
        info.EnvironmentVariables["LOCALAPPDATA"] = Path.Combine(data, "local");
        info.EnvironmentVariables["KURO_EXPECTED_USER_DIR"] = Path.Combine(data, "roaming", "Godot", "app_userdata", AppName);
        var output = new StringBuilder(); var gate = new object();
        using (var p = new Process { StartInfo = info }) {
            p.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock (gate) output.AppendLine(e.Data); };
            p.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) lock (gate) output.AppendLine(e.Data); };
            p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
            if (!visible && !p.WaitForExit(120000)) { p.Kill(); p.WaitForExit(); throw new Exception("后台检查超时；保留日志，请停止本次测试。"); }
            p.WaitForExit(); code = p.ExitCode;
        }
        string result = output.ToString(); File.WriteAllText(log, result, Encoding.UTF8); return result;
    }
    void BeginSession(bool isNew) {
        string exe = engine.Text.Trim().Trim('"');
        if (exe.Length == 0 || exe.StartsWith("\\\\") || !Path.IsPathRooted(exe) || !File.Exists(exe)) {
            MessageBox.Show(this, "找不到 Godot。请点击“选择 Godot EXE…”或输入已有 Godot 4.6.x EXE 的完整本地路径。\r\n未启动游戏；未创建或改动任何玩家进度。", "请选择有效 Godot 路径", MessageBoxButtons.OK, MessageBoxIcon.Information); return;
        }
        if (!File.Exists(Path.Combine(project, "project.godot"))) { MessageBox.Show(this, "启动器须放在完整项目旁边；找不到 project.godot。", "项目不完整"); return; }
        if (!isNew && sessions.SelectedItem == null) { MessageBox.Show(this, "没有可继续的隔离会话，请新建测试者。", "没有隔离会话"); return; }
        string id = isNew ? "Session-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0,6) : (string)sessions.SelectedItem;
        string data = Path.GetFullPath(Path.Combine(sessionsRoot, id));
        if (!data.StartsWith(Path.GetFullPath(sessionsRoot) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) { MessageBox.Show(this, "隔离路径校验失败，未启动。", "停止"); return; }
        busy = true; fresh.Enabled = resume.Enabled = browse.Enabled = engine.Enabled = false;
        SetStatus("准备隔离会话：" + id + "\r\n正在检查版本、导入资源和实际 user://。请勿关闭。" );
        ThreadPool.QueueUserWorkItem(delegate {
            try {
                Directory.CreateDirectory(privateRoot);
                Directory.CreateDirectory(data);
                Directory.CreateDirectory(Path.Combine(data, "roaming")); Directory.CreateDirectory(Path.Combine(data, "local"));
                File.WriteAllText(Path.Combine(data, "host-session.marker"), "StageB host isolation session", Encoding.UTF8);
                File.WriteAllText(Path.Combine(privateRoot, "engine-path.txt"), exe, Encoding.UTF8);
                string stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N").Substring(0,4);
                int code;
                string version = Run(exe, "--version", data, Path.Combine(data, stamp + "-version.log"), false, out code);
                if (code != 0 || !Regex.IsMatch(version, @"\b4\.6(?:\.|-)") || !version.Contains("Godot") && !version.Contains("official")) throw new Exception("所选 EXE 未确认是 Godot 4.6.x，已停止。请核对版本日志。");
                string imported = Run(exe, "--headless --editor --path " + Quote(project) + " --quit", data, Path.Combine(data, stamp + "-import.log"), false, out code);
                if (code != 0) throw new Exception("资源导入退出码 " + code + "；已停止，请保留日志。");
                string checkedPath = Run(exe, "--headless --path " + Quote(project) + " --script res://launcher/verify_user_data.gd", data, Path.Combine(data, stamp + "-paths.log"), false, out code);
                string actual = null;
                foreach (string line in checkedPath.Split('\n')) if (line.StartsWith("HOSTCHECK_USER_DIR=")) actual = line.Substring("HOSTCHECK_USER_DIR=".Length).Trim();
                string expected = Path.Combine(data, "roaming", "Godot", "app_userdata", AppName);
                if (code != 0 || actual == null || !String.Equals(Path.GetFullPath(actual), Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase)) throw new Exception("实际 user:// 与私有会话目录不一致或未取得；已停止，不回退到真实存档。");
                File.WriteAllText(Path.Combine(data, stamp + "-verified-path.txt"), "APPDATA=" + Path.Combine(data,"roaming") + "\r\nACTUAL_USER_DIR=" + actual + "\r\nEXPECTED_USER_DIR=" + expected + "\r\nMATCH=true\r\n", Encoding.UTF8);
                int errors = Regex.Matches(imported, @"(?m)^ERROR:").Count;
                SetStatus("会话：" + id + "\r\n实际 user:// 已匹配隔离会话。导入 ERROR 数：" + errors + "。\r\n正在游戏窗口中试玩；请正常退出，再在此继续同一会话。\r\n日志 ERROR 不能自动认定无害，请检查中文、按钮和画面。");
                string game = Run(exe, "--verbose --path " + Quote(project), data, Path.Combine(data, stamp + "-game.log"), true, out code);
                string progress = Path.Combine(expected, "progress.cfg");
                int completed = File.Exists(progress) ? Regex.Matches(File.ReadAllText(progress), @"(?m)^\d+=\d+\s*$").Count : 0;
                string digest = "absent";
                if (File.Exists(progress)) using (var sha = SHA256.Create()) digest = BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(progress))).Replace("-","").ToLowerInvariant();
                File.WriteAllText(Path.Combine(data, stamp + "-result.txt"), "SESSION="+id+"\r\nEXIT_CODE="+code+"\r\nRECORDED_ENTRIES="+completed+"\r\nPROGRESS_SHA256="+digest+"\r\nIMPORT_ERROR_COUNT="+errors+"\r\n", Encoding.UTF8);
                SetStatus("已正常返回主持人窗口。\r\n会话：" + id + "\r\n退出码：" + code + "；隔离进度记录数：" + completed + "\r\n导入 ERROR 数：" + errors + "（保留日志，不等同于无影响）。\r\n重启选择同一会话，点击“继续选中测试”；另一位玩家请新建会话。\r\n日志仅在 .host-private 内，不会自动上传。");
            } catch (Exception e) { SetStatus("未完成启动/试玩：" + SafeMessage(e.Message) + "\r\n请保留本机会话日志；不要改用真实存档或绕过 Windows 安全提示。"); }
            finally { BeginInvoke(new Action(delegate { busy = false; engine.Enabled = browse.Enabled = fresh.Enabled = true; RefreshSessions(id); })); }
        });
    }
}
