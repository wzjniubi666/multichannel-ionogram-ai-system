using System;
using System.IO;
using System.Diagnostics;
using System.Windows.Forms;
internal static class SystemLauncher {
    [STAThread] static void Main() {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            string script=Path.Combine(root,"host","deploy","start_system.ps1");
            if(!File.Exists(script))throw new FileNotFoundException("Missing host/deploy/start_system.ps1");
            ProcessStartInfo p=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""+script+"\"");
            p.WorkingDirectory=root;p.UseShellExecute=false;p.CreateNoWindow=true;p.WindowStyle=ProcessWindowStyle.Hidden;
            using(Process child=Process.Start(p)) {
                child.WaitForExit();
                if(child.ExitCode!=0)MessageBox.Show("Unable to start Python. Configure hub_python in host/deploy/system_settings.json.","System launcher");
            }
        } catch(Exception e) { MessageBox.Show(e.Message,"System launcher"); }
    }
}
