"""Regression for the actual Windows Python -> PowerShell -> Python event path."""
from pathlib import Path
from contextlib import closing
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import numpy as np

APP=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(APP))
import backend as core
import worker
from live_preview import create_data,apply_pixel,metadata
from m512_active14_scan import Emulated512Socket


def evidence(name,value):
    directory=os.environ.get('BEAMFORMING_TEST_EVIDENCE')
    if directory:
        path=Path(directory);path.mkdir(parents=True,exist_ok=True)
        (path/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


class LiveProgressTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='live_test_',dir=APP/'validation')
        self.folder=Path(self.temp.name)
        self.plan=core.verify_plan(core.RELEASE/'actual11_plan14_v2')

    def tearDown(self):
        assert self.folder.resolve().is_relative_to((APP/'validation').resolve())
        self.temp.cleanup()

    def request(self,name='result'):
        return dict(mode='emulator',plan_directory=str(self.plan.path),result_directory=str(self.folder/name),
                    owner_pid=os.getpid(),stop_file=str(self.folder/'stop'),resume=False)

    def test_each_live_pixel_is_committed_before_final_aggregation(self):
        from m512_active14_scan import Journal512
        request=self.request();events=[];committed=[]
        original_finish=Journal512.finish
        def finish(journal,attempt,ordinal,trace,elapsed,error=None):
            original_finish(journal,attempt,ordinal,trace,elapsed,error)
            if error is None:
                self.assertFalse(journal.db.in_transaction)
                committed.append(ordinal)
        def inspect(count):
            self.assertFalse((Path(request['result_directory'])/'scan_results.npz').exists())
            point=[e for e in events if e['kind']=='pixel'][-1]
            self.assertEqual(point['ordinal'],count-1)
            self.assertEqual(len(committed),count)
        with patch.object(Journal512,'finish',finish),patch.object(worker,'emit',lambda kind,**kw:events.append(dict(kind=kind,**kw))):
            worker.run_scan(request,after_frame=inspect)
        data=create_data(next(e for e in events if e['kind']=='preview'))
        for event in events:
            if event['kind']=='pixel':apply_pixel(data,event)
        final=core.load_result(request['result_directory'])
        np.testing.assert_array_equal(data.board,final.board)
        np.testing.assert_array_equal(data.single,final.single)
        self.assertEqual([e['completed'] for e in events if e['kind']=='progress'][-1],9)
        self.assertEqual(data.summary['source'],'emulator')

    def test_resume_initializes_saved_pixels_and_failure_cannot_paint(self):
        request=self.request();events=[]
        def stop(n):
            if n==1:Path(request['stop_file']).touch()
        with patch.object(worker,'emit',lambda *a,**k:None):worker.run_scan(request,after_frame=stop)
        Path(request['stop_file']).unlink();request['resume']=True
        with patch.object(worker,'emit',lambda kind,**kw:events.append(dict(kind=kind,**kw))):worker.run_scan(request)
        self.assertEqual(len(next(e for e in events if e['kind']=='preview')['pixels']),1)
        self.assertEqual(len([e for e in events if e['kind']=='pixel']),8)
        class Bad(Emulated512Socket):
            def recv(self,size):
                value=super().recv(size)
                return value[:-1]+bytes([value[-1]^1])
        events.clear()
        with patch.object(worker,'emit',lambda kind,**kw:events.append(dict(kind=kind,**kw))):
            with self.assertRaises(ValueError):worker.run_scan(self.request('bad'),sock=Bad())
        self.assertFalse(any(e['kind']=='pixel' for e in events))

    def test_windows_nested_pipe_delivers_progress_while_scan_is_running(self):
        request=self.request('nested');path=self.folder/'request.json';core.write_json(path,request)
        session=str(APP/'network_session.ps1').replace("'","''")
        ps=self.folder/'relay.ps1'
        ps.write_text("param([string]$RequestFile)\n$relayRequestFile=$RequestFile\n. '"+session+"'\n"
                      "$request=Get-Content -LiteralPath $relayRequestFile -Raw -Encoding UTF8 | ConvertFrom-Json\n"
                      "Invoke-GuiPacketWorker $request $relayRequestFile\n",encoding='utf-8-sig')
        command=['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ps),'-RequestFile',str(path)]
        driver=self.folder/'driver.py'
        driver.write_text('import sys\nsys.path.insert(0,'+repr(str(APP))+')\n'
                          'from live_preview import relay_process\nraise SystemExit(relay_process('+repr(command)+'))\n',encoding='utf-8')
        events=[];midway=False;output=[]
        with subprocess.Popen([str(core.PYTHON),'-E','-X','utf8','-u',str(driver)],stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,encoding='utf-8',creationflags=subprocess.CREATE_NO_WINDOW) as proc:
            for line in proc.stdout:
                output.append(line)
                if line.startswith('GUI_EVENT '):
                    event=json.loads(line[10:]);events.append(event)
                    if event['kind']=='progress' and 0<event['completed']<9:
                        midway |= not (self.folder/'scan_worker_result.json').exists()
            self.assertEqual(proc.wait(timeout=30),0,''.join(output))
        self.assertTrue(midway,'Windows grandchild progress arrived only after final result')
        self.assertEqual(len([e for e in events if e['kind']=='pixel']),9)
        evidence('nested_process_events.json',dict(progress_received_before_final_save=midway,
                 events=events,real_network_traffic=False))

    def test_native_plot_and_progress_update_before_job_finishes(self):
        import app
        gui=app.HostApp(auto_load=False)
        gui.settings_file=self.folder/'settings.json'
        snapshots=[]
        draw=gui._draw_selected
        def observed_draw():
            draw()
            if gui.busy and gui.result_data is not None:
                n=int(gui.result_data.complete.sum())
                if 0<n<gui.result_data.complete.size:
                    name=next((n for n,t in gui.tabs.items() if str(t)==gui.notebook.select()),'mvdr')
                    plotted=gui.figures[name].axes[0].collections[0].get_array()
                    snapshots.append((n,int(plotted.count()),gui.progress_text.get()))
                    gui.figures[name].savefig(self.folder/'midway.png',dpi=90)
                    directory=os.environ.get('BEAMFORMING_TEST_EVIDENCE')
                    if directory:gui.figures[name].savefig(Path(directory)/'live_emulator_midway.png',dpi=110)
        gui._draw_selected=observed_draw
        try:
            gui.data_path.set(str(core.BASE/'M/20260714_110000'))
            gui.result_root.set(str(self.folder/'gui_results'));gui.quick.set(True)
            gui.start('emulator')
            deadline=time.monotonic()+100
            while time.monotonic()<deadline and (gui.busy or gui.result_data is None or gui.result_data.summary.get('live_preview')):
                gui.update();time.sleep(.02)
            self.assertFalse(gui.busy,'GUI live job timed out')
            self.assertTrue(snapshots,'No partial plot appeared before completion')
            self.assertTrue(all(n==drawn and '%' in text for n,drawn,text in snapshots))
            self.assertTrue((self.folder/'midway.png').exists())
            self.assertEqual(int(gui.result_data.complete.sum()),9)
            self.assertIn('100.0%',gui.progress_text.get())
            self.assertEqual(gui.result_data.summary['source'],'emulator')
            self.assertFalse(gui.result_data.summary.get('live_preview',False))
            self.assertNotIn('实时预览',gui.figures['mvdr']._suptitle.get_text())
            evidence('live_widget_observations.json',dict(partial_snapshots=snapshots,
                progress_before_completion=True,plot_before_completion=True,source='emulator',
                final_completed=int(gui.result_data.complete.sum()),hardware_test=False))
        finally:
            if gui.busy:
                gui.stop();deadline=time.monotonic()+30
                while gui.busy and time.monotonic()<deadline:gui.update();time.sleep(.03)
            gui.destroy()


if __name__=='__main__':unittest.main(verbosity=2)
