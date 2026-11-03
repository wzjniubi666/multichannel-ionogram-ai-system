"""Run this file in the yolo environment to open the FPGA image recognition app."""
from pathlib import Path
import os,sys,json,queue,threading,subprocess,time,datetime,secrets,shutil
import tkinter as tk
from tkinter import ttk,filedialog,messagebox
from PIL import Image,ImageTk,ImageOps
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
BG='#edf2f8';INK='#142b46';MUTED='#60758c';BLUE='#246bfd';WHITE='#ffffff'
class App:
    def __init__(self,root):
        self.root=root;root.title('电离图识别 · YOLO FPGA');root.geometry('1280x900');root.minsize(1040,760);root.configure(bg=BG)
        self.events=queue.Queue();self.busy=False;self.ready=False;self.input_path=None;self.result_path=None;self.photos={};self.images={};self.process=None;self.cancel=None;self.closing=False;self.started=None;self.mode=None;self.received_result=False
        self.auto=tk.BooleanVar(value=True);self.status=tk.StringVar(value='等待添加图片');self.percent=tk.DoubleVar(value=0);self.percent_text=tk.StringVar(value='0%');self.elapsed=tk.StringVar(value='耗时 0.0 秒')
        self.board_text=tk.StringVar(value='待初始化');self.link_text=tk.StringVar(value='尚未协商');self.stats=tk.StringVar(value='结果：等待识别');self.file_text=tk.StringVar(value='支持 PNG / JPG / BMP / TIFF / WebP')
        style=ttk.Style();style.theme_use('clam');style.configure('TButton',font=('Microsoft YaHei UI',10),padding=(14,8));style.configure('Accent.TButton',background=BLUE,foreground=WHITE,borderwidth=0);style.map('Accent.TButton',background=[('active','#1959db'),('disabled','#a8bddb')]);style.configure('TCheckbutton',background=BG,font=('Microsoft YaHei UI',10));style.configure('FPGA.Horizontal.TProgressbar',troughcolor='#e3eaf4',background=BLUE,borderwidth=0,lightcolor=BLUE,darkcolor=BLUE,thickness=12)
        root.option_add('*Font',('Microsoft YaHei UI',10))
        header=tk.Frame(root,bg=INK,height=82);header.pack(fill='x');header.pack_propagate(False)
        tk.Label(header,text='电离图识别  /  YOLO FPGA',font=('Microsoft YaHei UI',21,'bold'),bg=INK,fg=WHITE).pack(side='left',padx=24)
        tk.Label(header,text='XC7K325T  ·  千兆网口  ·  前 15 个卷积',font=('Microsoft YaHei UI',10),bg=INK,fg='#c4d4e8').pack(side='right',padx=24)
        cards=tk.Frame(root,bg=BG);cards.pack(fill='x',padx=22,pady=(16,10))
        for i,(title,var) in enumerate([('板卡状态',self.board_text),('最近网口协商',self.link_text),('当前权重',tk.StringVar(value='best.pt · 两类回波')),('计算配置',tk.StringVar(value='256 × 256 · 64 MAC'))]):
            card=tk.Frame(cards,bg=WHITE,highlightbackground='#dce5ef',highlightthickness=1);card.grid(row=0,column=i,sticky='nsew',padx=(0,10 if i<3 else 0));cards.columnconfigure(i,weight=1)
            tk.Label(card,text=title,bg=WHITE,fg=MUTED,font=('Microsoft YaHei UI',9)).pack(anchor='w',padx=14,pady=(10,3));tk.Label(card,textvariable=var,bg=WHITE,fg=INK,font=('Microsoft YaHei UI',12,'bold')).pack(anchor='w',padx=14,pady=(0,11))
        toolbar=tk.Frame(root,bg=BG);toolbar.pack(fill='x',padx=22,pady=(0,10))
        self.connect_button=ttk.Button(toolbar,text='连接 / 初始化板卡',command=lambda:self.start('initialize'));self.connect_button.pack(side='left')
        self.add_button=ttk.Button(toolbar,text='添加图片',command=self.choose);self.add_button.pack(side='left',padx=8)
        self.example_button=ttk.Button(toolbar,text='示例图片',command=lambda:self.receive_files([str(ROOT/'host/app/recognition/sample_images/image00.png')]));self.example_button.pack(side='left')
        ttk.Checkbutton(toolbar,text='添加后自动识别',variable=self.auto).pack(side='left',padx=14)
        self.start_button=ttk.Button(toolbar,text='开始识别',style='Accent.TButton',command=lambda:self.start('recognize'));self.start_button.pack(side='right')
        self.stop_button=ttk.Button(toolbar,text='停止',command=self.stop,state='disabled');self.stop_button.pack(side='right',padx=8)
        panels=tk.Frame(root,bg=BG);panels.pack(fill='both',expand=True,padx=22)
        panels.columnconfigure(0,weight=1,uniform='preview');panels.columnconfigure(1,weight=1,uniform='preview');panels.rowconfigure(0,weight=1)
        self.canvases={}
        for col,key,title in [(0,'input','原始图片 · 拖入这里添加'),(1,'result','识别后 · 真实 FPGA + 电脑后续网络')]:
            card=tk.Frame(panels,bg=WHITE,highlightbackground='#dce5ef',highlightthickness=1);card.grid(row=0,column=col,sticky='nsew',padx=(0,10) if col==0 else (0,0))
            tk.Label(card,text=title,bg=WHITE,fg=INK,font=('Microsoft YaHei UI',11,'bold')).pack(anchor='w',padx=16,pady=(13,8))
            canvas=tk.Canvas(card,bg=WHITE,highlightthickness=0);canvas.pack(fill='both',expand=True,padx=12,pady=(0,12));self.canvases[key]=canvas
            canvas.bind('<Configure>',lambda event,k=key:self.render(k));canvas.bind('<Double-Button-1>',lambda event,k=key:self.enlarge(k))
        self.canvases['input'].bind('<Button-1>',lambda event:self.choose() if not self.input_path and not self.busy else None)
        row=tk.Frame(root,bg=BG);row.pack(fill='x',padx=22,pady=(8,10))
        tk.Label(row,textvariable=self.file_text,bg=BG,fg=MUTED,anchor='w').pack(side='left',fill='x',expand=True)
        self.save_button=ttk.Button(row,text='另存检测图',command=self.save,state='disabled');self.save_button.pack(side='right')
        self.folder_button=ttk.Button(row,text='打开结果目录',command=self.open_folder,state='disabled');self.folder_button.pack(side='right',padx=8)
        tk.Label(root,textvariable=self.stats,bg=BG,fg=INK,anchor='w').pack(fill='x',padx=24,pady=(0,9))
        footer=tk.Frame(root,bg=WHITE,highlightbackground='#dce5ef',highlightthickness=1);footer.pack(fill='x',padx=22,pady=(0,18))
        progressrow=tk.Frame(footer,bg=WHITE);progressrow.pack(fill='x',padx=14,pady=(12,5))
        tk.Label(progressrow,textvariable=self.status,bg=WHITE,fg=INK,font=('Microsoft YaHei UI',10,'bold')).pack(side='left');tk.Label(progressrow,textvariable=self.elapsed,bg=WHITE,fg=MUTED).pack(side='right');tk.Label(progressrow,textvariable=self.percent_text,bg=WHITE,fg=BLUE).pack(side='right',padx=14)
        ttk.Progressbar(footer,variable=self.percent,maximum=100,style='FPGA.Horizontal.TProgressbar').pack(fill='x',padx=14,pady=(0,9))
        logframe=tk.Frame(footer,bg=WHITE);logframe.pack(fill='x',padx=14,pady=(0,12))
        self.log=tk.Text(logframe,height=7,wrap='word',bg='#f5f8fc',fg='#34495f',relief='flat',font=('Consolas',9),state='disabled');self.log.pack(side='left',fill='both',expand=True)
        scrollbar=ttk.Scrollbar(logframe,command=self.log.yview);scrollbar.pack(side='right',fill='y');self.log.configure(yscrollcommand=scrollbar.set)
        self.write_log('准备就绪。板卡上电并接好 JTAG、网线后，拖入图片即可自动初始化和识别。')
        self.write_log('电脑有线地址 192.0.2.2；板卡 192.0.2.1。程序不会修改电脑网络设置。')
        try:
            from win_file_drop import FileDrop
            self.drop=FileDrop(root,self.receive_files);self.write_log('Windows 文件拖入已启用。')
        except Exception as e:self.drop=None;self.write_log('拖入暂不可用，可点击添加图片：'+str(e))
        root.protocol('WM_DELETE_WINDOW',self.close);root.after(100,self.poll)
        root.bind('<Control-o>',lambda event:self.choose());root.bind('<F5>',lambda event:self.start('recognize'))
    def write_log(self,message):
        stamp=datetime.datetime.now().strftime('%H:%M:%S');self.log.configure(state='normal');self.log.insert('end',f'[{stamp}] {message}\n');self.log.see('end');self.log.configure(state='disabled')
    def choose(self):
        if self.busy:return
        p=filedialog.askopenfilename(title='选择要识别的图片',filetypes=[('图片','*.png *.jpg *.jpeg *.bmp *.tif *.tiff *.webp'),('所有文件','*.*')])
        if p:self.receive_files([p])
    def receive_files(self,files):
        if self.busy:self.write_log('当前任务进行中，请完成或停止后再添加图片。');return
        candidates=[Path(p) for p in files if Path(p).is_file() and Path(p).suffix.lower() in {'.png','.jpg','.jpeg','.bmp','.tif','.tiff','.webp'}]
        if not candidates:self.status.set('请选择可读取的图片文件');self.write_log('未收到支持的图片。');return
        p=candidates[0]
        try:
            with Image.open(p) as im:image=ImageOps.exif_transpose(im).convert('RGB').copy()
        except Exception as e:self.status.set('图片读取失败');self.write_log(str(e));return
        self.input_path=p;self.images['input']=image;self.images.pop('result',None);self.result_path=None;self.percent.set(0);self.percent_text.set('0%');self.stats.set('结果：等待识别');self.file_text.set(f'{p.name}  ·  {image.width} × {image.height}');self.save_button.configure(state='disabled');self.folder_button.configure(state='disabled');self.render('input');self.render('result');self.write_log('已添加图片：'+str(p))
        if len(candidates)>1:self.write_log('当前为单图模式，本次使用第一张图片。')
        if self.auto.get():self.root.after(100,lambda:self.start('recognize'))
        else:self.status.set('图片已添加，点击开始识别')
    def render(self,key):
        c=self.canvases[key];w,h=c.winfo_width(),c.winfo_height()
        if w<20 or h<20:return
        c.delete('all')
        if key in self.images:
            im=self.images[key].copy();im.thumbnail((max(1,w-20),max(1,h-20)),Image.Resampling.LANCZOS);photo=ImageTk.PhotoImage(im);self.photos[key]=photo;c.create_image(w/2,h/2,image=photo)
        else:
            c.create_rectangle(8,8,w-8,h-8,outline='#c8d6e7',dash=(7,5),width=2)
            c.create_text(w/2,h/2-40,text='＋' if key=='input' else '识别后',fill=BLUE if key=='input' else '#91a5bb',font=('Microsoft YaHei UI',34 if key=='input' else 25))
            c.create_text(w/2,h/2+12,text='将图片拖入此处，或点击添加图片' if key=='input' else '检测图会显示在这里',fill=MUTED,font=('Microsoft YaHei UI',11))
    def set_busy(self,value):
        self.busy=value
        for b in [self.connect_button,self.add_button,self.example_button,self.start_button]:b.configure(state='disabled' if value else 'normal')
        self.stop_button.configure(state='normal' if value else 'disabled')
    def start(self,mode):
        if self.busy:return
        if mode=='recognize' and not self.input_path:self.status.set('请先在左侧添加一张图片');return
        self.mode=mode;self.received_result=False;self.received_failure=False;self.started=time.perf_counter();self.set_busy(True);self.percent.set(0);self.percent_text.set('0%');self.status.set('正在启动任务…')
        if mode=='recognize':self.images.pop('result',None);self.render('result');self.result_path=None;self.save_button.configure(state='disabled');self.stats.set('正在识别，请查看下方进度…')
        self.job_dir=ROOT/'metrics/runs/recognition/gui'/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3));self.job_dir.mkdir(parents=True);self.cancel=self.job_dir/'cancel.signal'
        args=[sys.executable,str(ROOT/'host/app/recognition/gui_backend.py'),'--output',str(self.job_dir),'--cancel',str(self.cancel)]
        if mode=='initialize':args.append('--initialize-only')
        else:
            args.extend(['--image',str(self.input_path)])
            if self.ready:args.append('--reuse-board')
        try:
            self.process=subprocess.Popen(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',env=dict(os.environ,PYTHONUTF8='1',PYTHONDONTWRITEBYTECODE='1'),creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            threading.Thread(target=self.read_worker,args=(self.process,self.job_dir/'worker.log'),daemon=True).start()
        except Exception as e:self.events.put(dict(event='error',message=str(e)));self.events.put(dict(event='exit',code=1))
    def read_worker(self,process,path):
        with path.open('w',encoding='utf-8') as log:
            for line in process.stdout:
                log.write(line);log.flush()
                try:event=json.loads(line)
                except (ValueError,TypeError):event=dict(event='log',message=line.strip())
                if isinstance(event,dict):self.events.put(event)
        self.events.put(dict(event='exit',code=process.wait()))
    def poll(self):
        if self.busy and self.started:self.elapsed.set(f'耗时 {time.perf_counter()-self.started:.1f} 秒')
        try:
            while True:
                e=self.events.get_nowait();kind=e.get('event')
                if kind=='progress':
                    p=float(e['percent']);self.percent.set(p);self.percent_text.set(f'{p:.0f}%');self.status.set(e['message']);self.write_log(e['message'])
                elif kind=='log':
                    if e.get('message'):self.write_log(e['message'])
                elif kind=='connected':
                    self.ready=True;self.board_text.set('已连接 · 配置已验证');self.link_text.set('1000 Mbps · 全双工');self.write_log(f"PHY 接收时钟：{e['link']['rx_clock_khz']/1000:.3f} MHz")
                elif kind=='initialized':self.received_result=True;self.status.set('板卡初始化完成，可添加图片')
                elif kind=='result':
                    self.received_result=True;r=e['report'];self.result_path=Path(r['output_image'])
                    with Image.open(self.result_path) as im:self.images['result']=im.convert('RGB').copy()
                    self.render('result');self.save_button.configure(state='normal');self.folder_button.configure(state='normal');self.stats.set(f"检出 {len(r['detections'])} 个目标  |  FPGA 计算 {r['fpga_compute_ms']:.2f} ms  |  65536/65536 特征校验通过  |  UDP 重试 {r['udp_retries']}")
                    for ob in r['detections']:self.write_log(f"检测：{ob['class_name']}  {ob['confidence']*100:.2f}%")
                    self.write_log('图片与报告已保存到：'+str(self.result_path.parent))
                elif kind in ('error','cancelled'):
                    self.received_failure=True;self.ready=False;self.board_text.set('待重新初始化');self.status.set(e.get('message','任务失败'));self.write_log(('错误：' if kind=='error' else '')+e.get('message','任务失败'))
                elif kind=='exit':
                    self.set_busy(False)
                    if e['code']==0 and not self.received_result:self.status.set('任务未返回有效结果，请查看日志')
                    elif e['code']!=0 and not self.received_failure:self.ready=False;self.board_text.set('待重新初始化');self.status.set('任务失败，请查看下方日志');self.write_log(f'后台退出代码：{e["code"]}')
                    if self.closing:self.destroy();return
        except queue.Empty:pass
        self.root.after(100,self.poll)
    def stop(self):
        if self.busy and self.cancel:
            self.cancel.touch();self.stop_button.configure(state='disabled');self.status.set('正在停止，当前板卡配置步骤完成后会安全退出…');self.write_log('已请求停止。')
    def enlarge(self,key):
        if key not in self.images:return
        top=tk.Toplevel(self.root);top.title('原始图片' if key=='input' else '识别结果');top.geometry('1100x800');canvas=tk.Canvas(top,bg=WHITE);canvas.pack(fill='both',expand=True)
        def paint(event=None):
            im=self.images[key].copy();im.thumbnail((max(1,canvas.winfo_width()-16),max(1,canvas.winfo_height()-16)),Image.Resampling.LANCZOS);canvas.photo=ImageTk.PhotoImage(im);canvas.delete('all');canvas.create_image(canvas.winfo_width()/2,canvas.winfo_height()/2,image=canvas.photo)
        canvas.bind('<Configure>',paint)
    def save(self):
        if not self.result_path:return
        p=filedialog.asksaveasfilename(title='保存检测图',defaultextension='.jpg',filetypes=[('JPEG','*.jpg'),('PNG','*.png')])
        if p:
            with Image.open(self.result_path) as im:im.convert('RGB').save(p)
            self.write_log('检测图已另存为：'+p)
    def open_folder(self):
        if self.result_path and sys.platform=='win32':os.startfile(str(self.result_path.parent))
    def close(self):
        if self.busy:self.closing=True;self.stop();return
        self.destroy()
    def destroy(self):
        if self.drop:self.drop.close()
        self.root.destroy()
def main():
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--image',type=Path)
    args=parser.parse_args()
    root=tk.Tk();app=App(root)
    if args.image:
        app.auto.set(False)
        app.receive_files([str(args.image.resolve())])
    root.mainloop()
if __name__=='__main__':main()
