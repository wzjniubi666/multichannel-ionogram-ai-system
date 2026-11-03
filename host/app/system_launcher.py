"""Start the two existing applications from one project; no hardware work on startup."""
from pathlib import Path
import argparse,json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
for name,folder in (('TCL_LIBRARY','tcl8.6'),('TK_LIBRARY','tk8.6')):
    library=ROOT/'host/app/beamforming/com/runtime/tcl'/folder
    if library.is_dir():os.environ[name]=str(library)
import tkinter as tk
from tkinter import ttk,filedialog,messagebox
import system_core as core

class SystemApp(tk.Tk):
    def __init__(self):
        super().__init__();self.title('电离图智能识别系统 · 波束合成 + YOLO');self.geometry('850x600');self.minsize(780,540)
        self.configure(bg='#eef2f7');self.config_data=core.settings()
        self.yolo_python=tk.StringVar(value=self.config_data.get('recognition_python',''))
        self.state_text=tk.StringVar(value='就绪 · 启动本界面不会配置或下载FPGA')
        style=ttk.Style(self);style.theme_use('clam');style.configure('TButton',padding=10,font=('Microsoft YaHei UI',11))
        tk.Label(self,text='电离图智能识别系统',bg='#213750',fg='white',font=('Microsoft YaHei UI',23,'bold'),padx=25,pady=20).pack(fill='x')
        content=tk.Frame(self,bg='#eef2f7',padx=25,pady=18);content.pack(fill='both',expand=True)
        tk.Label(content,text='两个阶段，一个工程',bg='#eef2f7',fg='#213750',font=('Microsoft YaHei UI',14,'bold')).pack(anchor='w')
        ttk.Button(content,text='① 打开波束合成上位机（实时进度 / 电离图）',command=self.open_beamforming).pack(fill='x',pady=(15,8))
        ttk.Button(content,text='② 打开 YOLO 电离图识别',command=lambda:self.open_recognition()).pack(fill='x',pady=8)
        ttk.Button(content,text='选择完整波束合成结果 → 导入识别图片',command=self.handoff).pack(fill='x',pady=8)
        config=tk.LabelFrame(content,text='YOLO Python环境',font=('Microsoft YaHei UI',10),bg='#eef2f7',padx=10,pady=10)
        config.pack(fill='x',pady=14)
        ttk.Entry(config,textvariable=self.yolo_python).pack(side='left',fill='x',expand=True)
        ttk.Button(config,text='选择 python.exe',command=self.choose_python).pack(side='left',padx=(8,0))
        tk.Label(content,text='同一板卡按阶段运行。YOLO初始化会替换波束合成镜像。\n先完成并退出上一阶段，再在识别界面明确启动初始化/识别。\n导入图片仅显示预览，不会自动下载、发包或开始识别。',justify='left',bg='#eef2f7',fg='#53647b',font=('Microsoft YaHei UI',10)).pack(anchor='w',pady=5)
        row=tk.Frame(content,bg='#eef2f7');row.pack(fill='x',pady=10)
        ttk.Button(row,text='项目文件夹',command=lambda:os.startfile(str(ROOT))).pack(side='left')
        ttk.Button(row,text='操作说明',command=lambda:os.startfile(str(ROOT/'README.md'))).pack(side='left',padx=8)
        tk.Label(self,textvariable=self.state_text,bg='#e1e8f0',fg='#334155',anchor='w',padx=22,pady=10).pack(fill='x',side='bottom')

    def choose_python(self):
        path=filedialog.askopenfilename(title='选择安装了PyTorch及YOLO依赖的Python',filetypes=[('Python','python.exe')])
        if path:
            self.yolo_python.set(path);self.config_data['recognition_python']=path
            core.SETTINGS.write_text(json.dumps(self.config_data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

    def open_beamforming(self):
        try:
            subprocess.Popen([str(ROOT/'host/app/beamforming/com/FPGAHost.exe')],cwd=ROOT/'host/app/beamforming/com',
                creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            self.state_text.set('已打开波束合成入口；请在其窗口中明确启动任务。')
        except Exception as exc:messagebox.showerror('无法启动',str(exc))

    def open_recognition(self,image=None):
        try:
            self.config_data['recognition_python']=self.yolo_python.get().strip()
            command=core.recognition_command(image,self.config_data)
            subprocess.Popen(command,cwd=ROOT,env=core.child_environment(),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            self.state_text.set('已打开识别界面；图片导入不会自动运行板卡。' if image else '已打开YOLO识别界面。')
        except Exception as exc:messagebox.showerror('需要配置YOLO运行环境',str(exc))

    def handoff(self):
        path=filedialog.askdirectory(title='选择已完成的波束合成结果（含scan_summary.json）')
        if not path:return
        try:
            image,manifest=core.handoff_result(path)
            self.state_text.set('已核验并复制电离图：'+str(image))
            self.open_recognition(image)
        except Exception as exc:messagebox.showerror('未交接图片',str(exc))

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');a=p.parse_args()
    if a.check:
        for name in ('host/app/beamforming/com/app.py','host/app/recognition/app_gui.py','host/model/recognition/best.pt','docs/architecture.md'):
            if not (ROOT/name).is_file():raise FileNotFoundError(name)
        print('PASS UNIFIED ENTRY: two application paths and model exist; no FPGA access.');return
    SystemApp().mainloop()
if __name__=='__main__':main()
