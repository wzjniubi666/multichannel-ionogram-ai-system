"""Windows file-drop support for this Tk app, using the native WM_DROPFILES API."""
import sys,ctypes
from ctypes import wintypes
class FileDrop:
    def __init__(self,root,callback):
        self.root=root;self.callback=callback;self.windows=set();self.refs=[]
        if sys.platform!='win32':raise RuntimeError('原生文件拖入仅支持 Windows；其他系统请使用添加图片按钮。')
        self.user=ctypes.WinDLL('user32',use_last_error=True);self.shell=ctypes.WinDLL('shell32',use_last_error=True);self.com=ctypes.WinDLL('comctl32',use_last_error=True)
        LRESULT=ctypes.c_ssize_t;PTR=ctypes.c_size_t
        self.PROC=ctypes.WINFUNCTYPE(LRESULT,wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM,PTR,PTR)
        self.com.SetWindowSubclass.argtypes=[wintypes.HWND,self.PROC,PTR,PTR];self.com.SetWindowSubclass.restype=wintypes.BOOL
        self.com.RemoveWindowSubclass.argtypes=[wintypes.HWND,self.PROC,PTR];self.com.RemoveWindowSubclass.restype=wintypes.BOOL
        self.com.DefSubclassProc.argtypes=[wintypes.HWND,wintypes.UINT,wintypes.WPARAM,wintypes.LPARAM];self.com.DefSubclassProc.restype=LRESULT
        self.shell.DragAcceptFiles.argtypes=[wintypes.HWND,wintypes.BOOL]
        self.shell.DragQueryFileW.argtypes=[wintypes.HANDLE,wintypes.UINT,wintypes.LPWSTR,wintypes.UINT];self.shell.DragQueryFileW.restype=wintypes.UINT
        self.shell.DragFinish.argtypes=[wintypes.HANDLE]
        self.user.GetAncestor.argtypes=[wintypes.HWND,wintypes.UINT];self.user.GetAncestor.restype=wintypes.HWND
        self.ENUM=ctypes.WINFUNCTYPE(wintypes.BOOL,wintypes.HWND,wintypes.LPARAM)
        self.user.EnumChildWindows.argtypes=[wintypes.HWND,self.ENUM,wintypes.LPARAM]
        self.proc=self.PROC(self._message);self.refs.append(self.proc)
        root.update_idletasks();outer=self.user.GetAncestor(root.winfo_id(),2)
        self.attach(outer);self.attach(root.winfo_id())
        cb=self.ENUM(lambda hwnd,param:self.attach(hwnd) or True);self.refs.append(cb);self.user.EnumChildWindows(outer,cb,0)
    def attach(self,hwnd):
        if hwnd and hwnd not in self.windows:
            if not self.com.SetWindowSubclass(hwnd,self.proc,0xF096,0):raise ctypes.WinError(ctypes.get_last_error())
            self.shell.DragAcceptFiles(hwnd,True);self.windows.add(hwnd)
        return True
    def _message(self,hwnd,msg,wparam,lparam,subclass_id,data):
        if msg==0x233:
            try:
                count=self.shell.DragQueryFileW(wparam,0xffffffff,None,0);paths=[]
                for i in range(count):
                    length=self.shell.DragQueryFileW(wparam,i,None,0);buf=ctypes.create_unicode_buffer(length+1)
                    self.shell.DragQueryFileW(wparam,i,buf,length+1);paths.append(buf.value)
                self.root.after(0,lambda p=paths:self.callback(p))
            finally:self.shell.DragFinish(wparam)
            return 0
        if msg==0x82:
            self.com.RemoveWindowSubclass(hwnd,self.proc,subclass_id);self.windows.discard(hwnd)
        return self.com.DefSubclassProc(hwnd,msg,wparam,lparam)
    def close(self):
        for hwnd in list(self.windows):
            self.shell.DragAcceptFiles(hwnd,False);self.com.RemoveWindowSubclass(hwnd,self.proc,0xF096)
        self.windows.clear()
