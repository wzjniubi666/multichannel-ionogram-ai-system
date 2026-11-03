using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class Launcher {
    static bool IsWorkspace(string folder) {
        return File.Exists(Path.Combine(folder, "XCK325Tboshuhecheng", "python", "m512_active14_release.py"))
            && File.Exists(Path.Combine(folder, ".venv-cos", "Scripts", "pythonw.exe"))
            && File.Exists(Path.Combine(folder, "HFceshi", "m255a.mat"));
    }
    static string FindWorkspace(string folder) {
        string config = Path.Combine(folder, "workspace.path");
        if (File.Exists(config)) {
            string value = File.ReadAllText(config, System.Text.Encoding.UTF8).Trim().TrimStart('\uFEFF');
            string path = Path.GetFullPath(Path.IsPathRooted(value) ? value : Path.Combine(folder, value));
            if (IsWorkspace(path)) return path;
            throw new DirectoryNotFoundException("workspace.path指向的原工程不完整：" + path);
        }
        DirectoryInfo parent = Directory.GetParent(folder.TrimEnd(Path.DirectorySeparatorChar));
        while (parent != null) {
            if (IsWorkspace(parent.FullName)) return parent.FullName;
            parent = parent.Parent;
        }
        throw new DirectoryNotFoundException("未找到原工作区。请先运行host/deploy/configure_desktop.ps1配置原工程位置。");
    }
    [STAThread]
    static void Main() {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        if (!File.Exists(Path.Combine(folder, "app.py")))
            folder = Directory.GetParent(folder.TrimEnd(Path.DirectorySeparatorChar)).FullName;
        string app = Path.Combine(folder, "app.py");
        if (!File.Exists(app)) {
            MessageBox.Show("未找到app.py。请保留上位机目录的完整结构。", "FPGA上位机");
            return;
        }
        try {
            string workspace = FindWorkspace(folder);
            string python = Path.Combine(workspace, ".venv-cos", "Scripts", "pythonw.exe");
            ProcessStartInfo info = new ProcessStartInfo(python, "-E -X utf8 \"" + app + "\"");
            info.WorkingDirectory = folder;
            info.UseShellExecute = true;
#if !PREVIEW
            info.Verb = "runas";
#endif
            Process.Start(info);
        } catch (Win32Exception ex) {
            MessageBox.Show(ex.NativeErrorCode == 1223 ? "启动已取消。实板通信需要管理员权限；可重新启动。" : ex.Message, "FPGA上位机");
        } catch (Exception ex) {
            MessageBox.Show(ex.Message, "FPGA上位机启动失败");
        }
    }
}
