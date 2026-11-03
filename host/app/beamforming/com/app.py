"""Native desktop host for the project's verified ACTIVE14 FPGA image."""
from __future__ import annotations
from pathlib import Path
import ctypes
import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import traceback
# The project's portable Python keeps Tcl scripts outside the venv prefix.
# Bind this process to its own matching runtime; do not edit system settings.
for _name, _folder in (('TCL_LIBRARY','tcl8.6'), ('TK_LIBRARY','tk8.6')):
    _library = Path(__file__).resolve().parent/'runtime/tcl'/_folder
    if not _library.is_dir():_library = Path(sys.base_prefix)/'tcl'/_folder
    if _library.is_dir():os.environ[_name] = str(_library)
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter.scrolledtext import ScrolledText
import backend as core
from live_preview import create_data, apply_pixel


class SoftCard(tk.Canvas):
    """Rounded white surface with an inset content frame, no raised border."""
    def __init__(self, parent, **kwargs):
        super().__init__(parent, bg='#f2f4f7', highlightthickness=0, bd=0, **kwargs)
        self.surface=self.create_polygon(0,0,0,0,fill='white',outline='',smooth=True,splinesteps=24)
        self.content=tk.Frame(self,bg='white',bd=0)
        self.window=self.create_window(10,9,window=self.content,anchor='nw')
        self.bind('<Configure>',self._resize)
    def _resize(self,event):
        w,h,r=event.width,event.height,12
        self.coords(self.surface,r,0,w-r,0,w,0,w,r,w,h-r,w,h,w-r,h,r,h,0,h,0,h-r,0,r,0,0)
        self.itemconfigure(self.window,width=max(1,w-20),height=max(1,h-18))


class Hint:
    def __init__(self,widget,text):
        self.widget,self.text,self.popup,self.timer=widget,text,None,None
        widget.bind('<Enter>',self.schedule,add='+')
        widget.bind('<Leave>',self.hide,add='+')
        widget.bind('<ButtonPress>',self.hide,add='+')
    def schedule(self,event=None):
        self.timer=self.widget.after(650,self.show)
    def show(self):
        self.timer=None
        self.popup=tk.Toplevel(self.widget);self.popup.wm_overrideredirect(True)
        self.popup.wm_geometry(f'+{self.widget.winfo_rootx()+8}+{self.widget.winfo_rooty()+self.widget.winfo_height()+5}')
        tk.Label(self.popup,text=self.text,bg='#26364b',fg='white',font=('Microsoft YaHei UI',9),
                 padx=10,pady=7,wraplength=340,justify='left').pack()
    def hide(self,event=None):
        if self.timer:
            self.widget.after_cancel(self.timer);self.timer=None
        if self.popup:self.popup.destroy();self.popup=None


class HostApp(tk.Tk):
    def __init__(self, auto_load=True):
        super().__init__()
        self.title('FPGA 波束合成上位机 · ACTIVE14 · 实时版')
        width=min(1370,max(1050,self.winfo_screenwidth()-80))
        height=min(920,max(680,self.winfo_screenheight()-100))
        self.geometry(f'{width}x{height}'); self.minsize(1050, 680)
        self.configure(bg='#f2f4f7')
        self.events = queue.Queue()
        self.busy = False; self.closing = False
        self.request_file = None; self.result_data = None
        self.backup_directory = None; self.result_directory = None
        self.started = 0.; self.initial_completed = None
        self.canvases = {}; self.figures = {}; self.chart_dirty = False
        self.live_dirty=False; self.live_next_draw=0.
        self.settings_file = core.APP/'settings.json'
        try:self.settings = core.read_json(self.settings_file) if self.settings_file.exists() else {}
        except (OSError,ValueError):self.settings = {}
        self.data_path = tk.StringVar(value=self.settings.get('data_folder', str(core.BASE/'M/20260617_160000')))
        self.result_root = tk.StringVar(value=self.settings.get('result_root', str(Path(__file__).resolve().parents[4]/'metrics/runs/beamforming')))
        self.dataset_info = tk.StringVar(value='请选择16通道数据')
        self.connected = tk.BooleanVar(value=False)
        self.quick = tk.BooleanVar(value=False)
        self.normalization = tk.StringVar(value='独立背景（结构）')
        self.phase = tk.StringVar(value='就绪')
        self.mode_badge = tk.StringVar(value='电离图')
        self.progress_text = tk.StringVar(value='0 / 0')
        self.traffic_text = tk.StringVar(value='发送 0 MB  ·  接收 0 MB')
        self.time_text = tk.StringVar(value='用时 --  ·  剩余 --')
        self.network_text = tk.StringVar(value='网卡未检查')
        self._style(); self._build()
        self.protocol('WM_DELETE_WINDOW', self.on_close)
        self.after(80, self._poll)
        if auto_load:self.after(500, self._load_initial)

    def _style(self):
        style = ttk.Style(self); style.theme_use('clam')
        style.configure('.', font=('Microsoft YaHei UI', 10), background='#f2f4f7', foreground='#334155')
        style.configure('Card.TFrame', background='white',borderwidth=0)
        style.configure('Card.TLabel', background='white',foreground='#475569')
        style.configure('CardTitle.TLabel', background='white', font=('Microsoft YaHei UI', 11, 'bold'))
        style.configure('Muted.TLabel', background='white', foreground='#7b8594', font=('Microsoft YaHei UI', 9))
        style.configure('TButton', padding=(10, 6), background='#f0f3f7',foreground='#45566d',
                        borderwidth=0,relief='flat',lightcolor='#f0f3f7',darkcolor='#f0f3f7',bordercolor='#f0f3f7',focusthickness=1,focuscolor='#9aaabd')
        style.map('TButton', background=[('disabled','#f5f6f8'),('pressed','#dce4ee'),('active','#e5ebf2')],
                  foreground=[('disabled','#b0b7c2')],lightcolor=[('active','#e5ebf2')],darkcolor=[('active','#e5ebf2')],bordercolor=[('active','#e5ebf2')])
        style.configure('Primary.TButton', background='#365d88',foreground='white',font=('Microsoft YaHei UI',11,'bold'),
                        lightcolor='#365d88',darkcolor='#365d88',bordercolor='#365d88',padding=(10,8))
        style.map('Primary.TButton',background=[('disabled','#dce3eb'),('pressed','#28496e'),('active','#2e527c')],
                  foreground=[('disabled','#97a4b4'),('active','white')],
                  lightcolor=[('active','#2e527c')],darkcolor=[('active','#2e527c')],bordercolor=[('active','#2e527c')])
        style.configure('Stop.TButton',background='#edf0f4',foreground='#5d6879')
        style.configure('Quiet.TButton',background='white',foreground='#7b8594',padding=(4,2),font=('Microsoft YaHei UI',9))
        style.map('Quiet.TButton',background=[('active','#f5f7fa')])
        style.configure('TEntry',fieldbackground='#fafbfd',bordercolor='#e1e6ed',lightcolor='#e1e6ed',darkcolor='#e1e6ed',
                        borderwidth=1,padding=(8,6),insertcolor='#334155')
        style.map('TEntry',bordercolor=[('focus','#94a7be')],lightcolor=[('focus','#94a7be')],darkcolor=[('focus','#94a7be')])
        style.configure('TCombobox',fieldbackground='#f6f8fa',background='#f6f8fa',arrowcolor='#69788b',
                        bordercolor='#e8ecf1',lightcolor='#e8ecf1',darkcolor='#e8ecf1',padding=(7,5),borderwidth=1)
        style.map('TCombobox',fieldbackground=[('readonly','#f6f8fa')],selectbackground=[('readonly','#f6f8fa')],
                  selectforeground=[('readonly','#475569')],background=[('active','#edf1f6')])
        style.configure('TCheckbutton',background='white',font=('Microsoft YaHei UI',9),foreground='#64748b',indicatormargin=(0,2,7,2))
        style.map('TCheckbutton',background=[('active','white')],indicatorbackground=[('selected','#365d88'),('!selected','#fafbfd')])
        style.configure('Vertical.TScrollbar',background='#dbe1e9',troughcolor='white',bordercolor='white',
                        lightcolor='#dbe1e9',darkcolor='#dbe1e9',arrowcolor='#96a1af',arrowsize=10,gripcount=0,borderwidth=0)
        style.map('Vertical.TScrollbar',background=[('active','#c4ceda')])
        style.configure('Horizontal.TProgressbar',troughcolor='#edf0f4',background='#526f94',lightcolor='#526f94',darkcolor='#526f94',
                        bordercolor='#edf0f4',borderwidth=0,thickness=7)
        style.configure('TNotebook',background='white',borderwidth=0,tabmargins=(0,0,0,5))
        style.configure('TNotebook.Tab',padding=(15,7),background='#f4f6f9',foreground='#8490a0',borderwidth=0,
                        lightcolor='white',darkcolor='white',bordercolor='white')
        style.map('TNotebook.Tab',background=[('selected','white'),('active','#edf1f6')],
                  foreground=[('selected','#31547d')],lightcolor=[('selected','white')],darkcolor=[('selected','white')])

    def _build(self):
        header = tk.Frame(self,bg='#1e3048',height=68); header.pack(fill='x');header.pack_propagate(False)
        tk.Label(header,text='FPGA  波束合成',fg='#f8fafc',bg='#1e3048',font=('Microsoft YaHei UI',19,'bold')).pack(side='left',padx=26)
        tk.Label(header,text='14路有效  ·  512周期',fg='#aab9cb',bg='#1e3048',font=('Microsoft YaHei UI',10)).pack(side='right',padx=26)
        body = tk.Frame(self,bg='#f2f4f7');body.pack(fill='both',expand=True,padx=16,pady=14)
        side_card=SoftCard(body,width=350);side_card.pack(side='left',fill='y',padx=(0,12))
        side_outer=side_card.content
        side_scroll=ttk.Scrollbar(side_outer,orient='vertical');side_scroll.pack(side='right',fill='y')
        side_canvas=tk.Canvas(side_outer,bg='white',highlightthickness=0,yscrollcommand=side_scroll.set,width=320)
        side_canvas.pack(side='left',fill='both',expand=True); side_scroll.configure(command=side_canvas.yview)
        sidebar=ttk.Frame(side_canvas,style='Card.TFrame')
        side_window=side_canvas.create_window((0,0),window=sidebar,anchor='nw')
        sidebar.bind('<Configure>',lambda e:side_canvas.configure(scrollregion=side_canvas.bbox('all')))
        side_canvas.bind('<Configure>',lambda e:side_canvas.itemconfigure(side_window,width=e.width))
        self.side_canvas=side_canvas
        self.controls = []
        def label(text, style='CardTitle.TLabel', **kw):
            w = ttk.Label(sidebar,text=text,style=style,wraplength=290,**kw);w.pack(anchor='w',padx=12,pady=(13,7));return w
        def button(text, command, style='TButton'):
            w=ttk.Button(sidebar,text=text,command=command,style=style);w.pack(fill='x',padx=12,pady=3);self.controls.append(w);return w
        label('01  数据')
        entry=ttk.Entry(sidebar,textvariable=self.data_path);entry.pack(fill='x',padx=12,pady=4);self.controls.append(entry)
        line=ttk.Frame(sidebar,style='Card.TFrame');line.pack(fill='x',padx=12,pady=(2,0))
        for text, cmd in [('数据文件夹', self.choose_folder), ('16个文件', self.choose_files)]:
            w = ttk.Button(line, text=text, command=cmd); w.pack(side='left', expand=True, fill='x', padx=(0,3)); self.controls.append(w)
        ttk.Label(sidebar,textvariable=self.dataset_info,style='Muted.TLabel',wraplength=290).pack(fill='x',padx=12,pady=7)
        label('02  运行')
        out_entry=ttk.Entry(sidebar,textvariable=self.result_root);out_entry.pack(fill='x',padx=12,pady=4);self.controls.append(out_entry)
        button('保存位置', self.choose_output)
        q=ttk.Checkbutton(sidebar,text='快速验收（9点）',variable=self.quick);q.pack(anchor='w',padx=12,pady=5);self.controls.append(q)
        c=ttk.Checkbutton(sidebar,text='已下载14路镜像并直连',variable=self.connected);c.pack(anchor='w',padx=12,pady=5);self.controls.append(c)
        Hint(q,'仅运行3个频点、3个延迟，用于快速检查通信。')
        Hint(c,'确认已下载当前14路bit，并用网线直连电脑与FPGA。')
        self.start_button=button('开始合成',lambda:self.start('hardware'),'Primary.TButton')
        self.stop_button=ttk.Button(sidebar,text='停止并保存',command=self.stop,style='Stop.TButton',state='disabled')
        self.stop_button.pack(fill='x',padx=12,pady=3)
        Hint(self.stop_button,'完成当前操作后停止，保存已完成数据并自动恢复网卡。')
        button('继续任务',self.resume)
        offline=button('离线自测',lambda:self.start('emulator'));Hint(offline,'不连接FPGA，结果标记为模拟数据。')
        label('03  结果与网络')
        ttk.Label(sidebar,textvariable=self.network_text,style='Muted.TLabel',wraplength=290).pack(fill='x',padx=12,pady=4)
        check=button('检查网卡',self.inspect_network);Hint(check,'只读检查网卡和链路速率，不发送FPGA数据。')
        button('恢复网卡',self.restore_network)
        button('历史结果',self.open_history)
        button('结果目录',self.open_result_folder)
        ttk.Label(sidebar,text='07/15关闭 · 113°/35°\n结束后自动恢复网络',style='Muted.TLabel',wraplength=290).pack(side='bottom',fill='x',padx=12,pady=14)
        right = ttk.Frame(body); right.pack(side='left', fill='both', expand=True)
        progress_card=SoftCard(right,height=132);progress_card.pack(fill='x',pady=(0,10));progress=progress_card.content
        ttk.Label(progress,textvariable=self.phase,style='CardTitle.TLabel').pack(anchor='w',padx=10,pady=(5,7))
        row = ttk.Frame(progress, style='Card.TFrame'); row.pack(fill='x', padx=16)
        ttk.Label(row, textvariable=self.progress_text, style='Card.TLabel').pack(side='left')
        ttk.Label(row, textvariable=self.time_text, style='Muted.TLabel').pack(side='right')
        self.progress=ttk.Progressbar(progress,mode='determinate');self.progress.pack(fill='x',padx=16,pady=9)
        ttk.Label(progress, textvariable=self.traffic_text, style='Muted.TLabel').pack(anchor='w', padx=16, pady=(0,10))
        chart_card=SoftCard(right);chart_card.pack(fill='both',expand=True);chart=chart_card.content
        bar = ttk.Frame(chart, style='Card.TFrame'); bar.pack(fill='x', padx=10, pady=8)
        ttk.Label(bar, textvariable=self.mode_badge, style='CardTitle.TLabel').pack(side='left')
        self.norm_box=ttk.Combobox(bar,textvariable=self.normalization,state='readonly',width=17,
                                 values=['独立背景（结构）','共同背景'])
        self.norm_box.pack(side='right'); self.norm_box.bind('<<ComboboxSelected>>', lambda e:self.draw_charts())
        Hint(self.norm_box,'独立背景仅比较结构；共同背景以单通道为统一参考。512周期相干积累；非校准SNR，距离未校准，灰色为缺失。')
        self.notebook = ttk.Notebook(chart); self.notebook.pack(fill='both', expand=True, padx=7, pady=(0,7))
        self.tabs = {}
        for name,text in [('mvdr','波束合成'),('single','单通道'),('compare','对比')]:
            tab = ttk.Frame(self.notebook, style='Card.TFrame'); self.tabs[name]=tab; self.notebook.add(tab, text=text)
            ttk.Label(tab,text='选择数据开始，或打开历史结果',
                      style='Muted.TLabel', anchor='center').pack(fill='both', expand=True)
        self.notebook.bind('<<NotebookTabChanged>>', self._tab_changed)
        self.logs_card=SoftCard(right,height=44);self.logs_card.pack(fill='x',pady=(10,0));logs=self.logs_card.content
        log_header=ttk.Frame(logs,style='Card.TFrame');log_header.pack(fill='x',padx=10)
        ttk.Label(log_header,text='日志',style='Muted.TLabel').pack(side='left',pady=3)
        self.log_toggle=ttk.Button(log_header,text='展开',style='Quiet.TButton',command=self.toggle_logs)
        self.log_toggle.pack(side='right')
        self.logs_expanded=False
        self.log=ScrolledText(logs,height=4,wrap='word',bg='#fafbfd',fg='#66758a',relief='flat',borderwidth=0,highlightthickness=0,font=('Consolas',9))
        self.log.configure(state='disabled')
        self._log('就绪。')
        def wheel(event):
            side_canvas.yview_scroll(-int(event.delta/120),'units'); return 'break'
        def bind_wheel(widget):
            widget.bind('<MouseWheel>',wheel,add='+')
            for child in widget.winfo_children():bind_wheel(child)
        bind_wheel(sidebar)

    def toggle_logs(self):
        self.logs_expanded=not self.logs_expanded
        self.logs_card.configure(height=115 if self.logs_expanded else 44)
        self.log_toggle.configure(text='收起' if self.logs_expanded else '展开')
        if self.logs_expanded:self.log.pack(fill='x',padx=10,pady=(0,8))
        else:self.log.pack_forget()

    def report_callback_exception(self, kind, value, tb):
        text=''.join(traceback.format_exception(kind,value,tb))
        (core.APP/'ui_error.log').write_text(text,encoding='utf-8')
        self._log('界面错误：'+str(value))

    def _log(self, message):
        self.log.configure(state='normal')
        self.log.insert('end', time.strftime('%H:%M:%S  ') + str(message) + '\n')
        if int(self.log.index('end-1c').split('.')[0]) > 1500:
            self.log.delete('1.0','301.0')
        self.log.see('end'); self.log.configure(state='disabled')

    def _save_settings(self):
        core.write_json(self.settings_file, dict(data_folder=self.data_path.get(), result_root=self.result_root.get(),
                        last_result=str(self.result_directory) if self.result_directory else ''))

    def _validate(self, selected=None):
        try:
            info = core.validate_capture(self.data_path.get(), selected)
            cap = info['capture']
            self.dataset_info.set(f'{cap[4:6]}-{cap[6:8]} {cap[9:11]}:{cap[11:13]} · 16通道 · {info["frequency_points"]}频点')
            self._save_settings(); return info
        except Exception as exc:
            self.dataset_info.set('数据检查未通过：'+str(exc)); raise

    def choose_folder(self):
        path = filedialog.askdirectory(title='选择含00～15通道COS文件的数据文件夹', initialdir=str(core.BASE/'M'))
        if path:
            self.data_path.set(path)
            try:self._validate()
            except Exception as exc:messagebox.showerror('数据不完整', str(exc))

    def choose_files(self):
        paths = filedialog.askopenfilenames(title='选择同一时刻全部16个COS文件', initialdir=str(core.BASE/'M'), filetypes=[('COS数据','*.cos')])
        if paths:
            self.data_path.set(str(Path(paths[0]).parent))
            try:self._validate(paths)
            except Exception as exc:messagebox.showerror('文件选择不匹配',str(exc))

    def choose_output(self):
        path = filedialog.askdirectory(title='选择结果保存根目录', initialdir=self.result_root.get())
        if path:self.result_root.set(path); self._save_settings()

    def _set_busy(self, value):
        self.busy=value
        for widget in self.controls:
            widget.configure(state='disabled' if value else 'normal')
        self.stop_button.configure(state='normal' if value and self.request_file else 'disabled')
        if not value:self.progress.stop()

    def start(self, mode, resume_directory=None):
        if self.busy:return
        if mode == 'hardware' and not core.is_admin():
            messagebox.showerror('需要管理员权限', '请关闭窗口，双击com文件夹里的“启动上位机.vbs”，在Windows提示中允许管理员权限。'); return
        if mode == 'hardware' and not self.connected.get():
            messagebox.showinfo('确认连接','请下载14路bit并连接直连网线，再勾选“已下载14路镜像并直连”。');return
        try:
            if resume_directory:
                previous=core.read_json(Path(resume_directory)/'scan_summary.json')
                from m512_active14_plan import Plan512
                plan=Plan512(previous['plan_directory'])
                self.data_path.set(plan.meta['capture_directory'])
            info=self._validate()
            job=core.APP/'jobs'/core.stamp(); job.mkdir(parents=True)
            output=Path(resume_directory).resolve() if resume_directory else Path(self.result_root.get()).resolve()/info['capture']/(mode+'_'+core.stamp())
            request=dict(mode=mode, data_folder=info['folder'], result_directory=str(output),
                         quick=self.quick.get(), resume=bool(resume_directory), stop_file=str(job/'cancel.request'),
                         owner_pid=os.getpid(), direct_connection_confirmed=self.connected.get())
            self.request_file=job/'request.json'; core.write_json(self.request_file,request)
            self.result_directory=output; self.started=time.monotonic(); self.initial_completed=None
            self.result_data=None; self.live_dirty=False; self.live_next_draw=0.
            for tab in self.tabs.values():
                for widget in tab.winfo_children():widget.destroy()
            self.canvases.clear();self.figures.clear()
            self.mode_badge.set('实板 · 等待已核验数据' if mode=='hardware' else '离线模拟 · 等待数据')
            self.progress_text.set('准备中…');self.traffic_text.set('尚未传输')
            self.phase.set('离线自测' if mode=='emulator' else '检查数据与镜像')
            self._set_busy(True); self.progress.configure(mode='indeterminate'); self.progress.start(15)
            self._log(f'新任务：{info["capture"]}，来源={mode}；日志 {job}')
            self._save_settings()
            threading.Thread(target=self._run_worker, args=(self.request_file,), daemon=True).start()
        except Exception as exc:messagebox.showerror('无法开始',str(exc)); self._log(exc)

    def _run_worker(self, request_path):
        try:
            command=[str(core.PYTHON),'-E','-X','utf8','-u',str(core.APP/'worker.py'),'job','--request',str(request_path)]
            with (request_path.parent/'worker.log').open('w',encoding='utf-8') as log:
                with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                      encoding='utf-8', errors='replace', cwd=core.APP,
                                      creationflags=subprocess.CREATE_NO_WINDOW) as process:
                    for line in process.stdout:
                        try:log.write(line); log.flush()
                        except OSError:self.events.put(('log','日志磁盘写入失败；仍继续接收工作进程状态并执行清理。'))
                        line=line.rstrip()
                        if line.startswith('GUI_EVENT '):
                            try:self.events.put(('worker',json.loads(line[10:])))
                            except ValueError:self.events.put(('log',line))
                        else:self.events.put(('log',line))
                    code=process.wait()
            outcome=core.read_json(request_path.parent/'outcome.json') if (request_path.parent/'outcome.json').exists() else dict(status='FAILED',error=f'工作进程异常退出：{code}')
            self.events.put(('finished',outcome))
        except Exception as exc:self.events.put(('finished',dict(status='FAILED',error=str(exc))))

    def stop(self):
        if self.busy and self.request_file:
            (self.request_file.parent/'cancel.request').touch()
            self.stop_button.configure(state='disabled')
            self.phase.set('停止中 · 保存并恢复网络')
            self._log('已请求安全停止；不会强制结束网络恢复进程。')

    def resume(self):
        path=filedialog.askdirectory(title='选择未完成任务（含scan_summary.json）的目录', initialdir=self.result_root.get())
        if not path:return
        try:
            summary=core.read_json(Path(path)/'scan_summary.json')
            if summary['status'].startswith('COMPLETE_'):raise ValueError('该任务已完成，无需继续')
            self.start(summary['source'],path)
        except Exception as exc:messagebox.showerror('无法继续',str(exc))

    def _worker_event(self, event):
        kind=event['kind']
        if kind=='stage':
            self.phase.set(event['name']); self._log(event['name']+' '+event.get('detail',''))
        elif kind=='plan':
            self.progress.stop(); self.progress.configure(mode='determinate',maximum=event['total'],value=0)
            self.progress_text.set('共 '+str(event['total'])+' 个位置')
        elif kind=='progress':
            n,total=event['completed'],event['total']
            if self.initial_completed is None:self.initial_completed=n
            self.progress.stop(); self.progress.configure(mode='determinate', maximum=total,value=n)
            self.progress_text.set(f'{n:,} / {total:,}  ·  {100*n/total:.1f}%')
            elapsed=event['elapsed']; fresh=n-self.initial_completed
            eta=(total-n)*elapsed/fresh if fresh>0 else None
            fmt=lambda v:f'{int(v)//60:02d}:{int(v)%60:02d}'
            self.time_text.set('用时 '+fmt(elapsed)+'  ·  剩余 '+(fmt(eta) if eta is not None else '--'))
            self.traffic_text.set(f'发送 {event["tx_bytes"]/1e6:.2f} MB  ·  接收 {event["rx_bytes"]/1e6:.2f} MB  ·  {event["tx_packets"]:,} / {event["rx_packets"]:,} 包')
        elif kind=='preview':
            if Path(event['path']).resolve()!=Path(self.result_directory).resolve():return
            self.result_data=create_data(event)
            for pixel in event.get('pixels',[]):apply_pixel(self.result_data,pixel)
            self._live_changed()
        elif kind=='pixel':
            if self.result_data is None or Path(event['path']).resolve()!=self.result_data.path.resolve():return
            apply_pixel(self.result_data,event)
            self._live_changed()
        elif kind=='backup':self.backup_directory=event['path']; self._log('网卡备份：'+event['path'])
        elif kind=='result':self.result_directory=Path(event['path']); self._log('已保存 '+event['status']+'：'+event['path'])
        elif kind=='network':
            self.backup_directory=event.get('backup_directory')
            self.network_text.set('网卡已恢复' if event.get('restored') else '恢复失败，请检查')
        elif kind=='log':self._log(event['message'])
        elif kind=='error':self._log('错误：'+event.get('error',''))

    def _finished(self, result):
        self._set_busy(False)
        self.live_dirty=False
        status=result['status']
        self.phase.set({'COMPLETE':'完成 · 已保存','CANCELLED':'已停止 · 已保存','FAILED':'失败 · 请查看日志'}.get(status,status))
        if result.get('result_directory'):self.result_directory=Path(result['result_directory'])
        self._log('任务状态：'+status+' '+result.get('error',result.get('message','')))
        if self.result_directory and (self.result_directory/'scan_results.npz').exists():
            self.load_history(self.result_directory)
        if status=='FAILED' and not self.closing:
            messagebox.showerror('任务未完成',result.get('error','请查看运行日志。')+'\n已完成记录不会丢弃。')
        if self.closing:self.after(100,self.destroy)

    def _poll(self):
        try:
            for _ in range(200):
                kind,data=self.events.get_nowait()
                if kind=='worker':self._worker_event(data)
                elif kind=='log':
                    if data:
                        self._log(data)
                        match=re.search(r'PREPARE HF (\d+)/(\d+)',data)
                        if match:
                            self.progress.stop(); self.progress.configure(mode='determinate',maximum=int(match[2]),value=int(match[1]))
                            self.progress_text.set(f'准备频点 {match[1]} / {match[2]}')
                elif kind=='finished':self._finished(data)
                elif kind=='loaded':
                    if self.busy:continue  # A late historical load must not replace the running preview.
                    self.result_data=data; self.result_directory=data.path
                    source='实板' if data.summary['source']=='hardware' else '离线模拟'
                    self.mode_badge.set(f'{source}  ·  {int(data.complete.sum())}/{data.complete.size}')
                    self.draw_charts(); self._save_settings()
                elif kind=='load_error':self._log('结果读取失败：'+str(data))
                elif kind=='network_info':self.network_text.set(data); self._log(data)
                elif kind=='restore_done':
                    self._set_busy(False); self.network_text.set(data); self.phase.set(data); self._log(data)
                    if self.closing:self.destroy(); return
        except queue.Empty:pass
        if self.live_dirty and time.monotonic()>=self.live_next_draw:
            self.live_dirty=False; self.live_next_draw=time.monotonic()+1.
            self.draw_charts()
        if self.winfo_exists():self.after(80,self._poll)

    def _live_changed(self):
        data=self.result_data
        source='实板' if data.summary['source']=='hardware' else '离线模拟'
        self.mode_badge.set(f'{source} · 实时预览 · {int(data.complete.sum())}/{data.complete.size}')
        self.live_dirty=True

    def draw_charts(self):
        if self.result_data is None:return
        self.chart_dirty=True
        self._draw_selected()

    def _tab_changed(self, event=None):
        if self.result_data is not None:self._draw_selected()

    def _draw_selected(self):
        from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
        if self.result_data is None:return
        name=next((n for n,t in self.tabs.items() if str(t)==self.notebook.select()),'mvdr')
        norm='common' if self.normalization.get()=='共同背景' else 'individual'
        key=(str(self.result_data.path),norm,int(self.result_data.complete.sum()),bool(self.result_data.summary.get('live_preview')))
        if self.canvases.get(name,{}).get('key')==key:return
        tab=self.tabs[name]
        for widget in tab.winfo_children():widget.destroy()
        fig=core.make_figure(self.result_data,name,norm)
        canvas=FigureCanvasTkAgg(fig,master=tab)
        toolbar=NavigationToolbar2Tk(canvas,tab,pack_toolbar=False)
        toolbar.configure(background='white',bd=0,highlightthickness=0)
        for widget in toolbar.winfo_children():
            try:widget.configure(background='white',borderwidth=0,highlightthickness=0)
            except tk.TclError:pass
            if isinstance(widget,(tk.Button,tk.Checkbutton)):
                widget.configure(relief='flat',activebackground='#edf1f6',activeforeground='#365d88')
                if isinstance(widget,tk.Checkbutton):widget.configure(selectcolor='#e4ebf3')
        toolbar.update();toolbar.pack(side='bottom',fill='x',pady=(3,0))
        canvas.get_tk_widget().configure(highlightthickness=0,borderwidth=0)
        canvas.get_tk_widget().pack(fill='both',expand=True); canvas.draw()
        self.figures[name]=fig; self.canvases[name]=dict(canvas=canvas,key=key)

    def load_history(self,path):
        def task():
            try:self.events.put(('loaded',core.load_result(path)))
            except Exception as exc:self.events.put(('load_error',exc))
        threading.Thread(target=task,daemon=True).start()

    def open_history(self):
        path=filedialog.askdirectory(title='选择含scan_results.npz的结果目录',initialdir=self.result_root.get())
        if path:self.load_history(Path(path))

    def _load_initial(self):
        try:self._validate()
        except Exception as exc:self._log(str(exc))
        last=self.settings.get('last_result')
        if not last:
            candidates=list((core.BASE/'result').glob('M*/scan_summary.json'))+list((core.BASE/'result').glob('M*/*/scan_summary.json'))
            candidates=[p for p in candidates if 'ACTIVE14' in p.parent.name]
            if candidates:last=str(max(candidates,key=lambda p:p.stat().st_mtime).parent)
        if last and (Path(last)/'scan_results.npz').exists():self.load_history(last)

    def open_result_folder(self):
        path=self.result_directory or Path(self.result_root.get())
        if path.exists():os.startfile(path)
        else:messagebox.showinfo('尚无结果','开始任务或打开历史结果后可查看。')

    def inspect_network(self):
        def task():
            try:
                command=['powershell.exe','-NoProfile','-NonInteractive','-Command',
                    "Get-NetAdapter -Physical | Where-Object {$_.InterfaceDescription -match 'Intel.*I219-V'} | Select-Object Name,Status,LinkSpeed,MacAddress | ConvertTo-Json -Compress"]
                done=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',
                                    timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
                if done.returncode:raise ValueError(done.stderr.strip())
                adapter=json.loads(done.stdout)
                if isinstance(adapter,list):raise ValueError('发现多块网卡，需核对现有配置')
                self.events.put(('network_info',f'{adapter["Name"]} · {adapter["Status"]} · {adapter["LinkSpeed"]}'))
            except Exception as exc:self.events.put(('network_info','网卡检查失败：'+str(exc)))
        threading.Thread(target=task,daemon=True).start()

    def restore_network(self):
        if self.busy:return
        if not core.is_admin():messagebox.showerror('需要管理员权限','请使用管理员启动入口。'); return
        initial=self.backup_directory or str(core.PROJECT/'validation/board_20261023')
        path=filedialog.askdirectory(title='选择含network_state.json的网卡备份目录',initialdir=initial)
        if not path:return
        base=(core.PROJECT/'validation/board_20261023').resolve()
        folder=Path(path).resolve()
        if not folder.is_relative_to(base) or not (folder/'network_state.json').exists():
            messagebox.showerror('备份无效','请选择项目validation/board_20261023内的实际网卡备份目录。'); return
        self.request_file=None; self._set_busy(True); self.phase.set('恢复网卡配置中，请等待')
        def task():
            command=['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
                     str(core.APP/'network_session.ps1'),'-RestoreDirectory',str(folder)]
            try:
                result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW)
                self.events.put(('log',result.stdout+result.stderr))
                self.events.put(('restore_done','网卡恢复已完成，请接回原网络线' if result.returncode==0 else '网卡恢复失败，请查看日志'))
            except Exception as exc:self.events.put(('restore_done','恢复失败：'+str(exc)))
        threading.Thread(target=task,daemon=True).start()

    def on_close(self):
        if self.busy:
            self.closing=True
            self.stop()
            self.phase.set('保存并恢复网络后关闭')
        else:
            self._save_settings(); self.destroy()

    def destroy(self):
        # Tk keeps scheduled Tcl commands until explicitly cancelled. Clear them
        # before destroying widgets, including canvas idle draws and UI polling.
        try:
            for timer in self.tk.call('after','info'):
                try:self.after_cancel(timer)
                except tk.TclError:pass
        except tk.TclError:pass
        super().destroy()


def main():
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID('Beamforming.ACTIVE14.Host')
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except (AttributeError,OSError):pass
    app=HostApp()
    app.mainloop()


if __name__=='__main__':
    try:main()
    except Exception:
        (core.APP/'startup_error.log').write_text(traceback.format_exc(),encoding='utf-8')
        raise
