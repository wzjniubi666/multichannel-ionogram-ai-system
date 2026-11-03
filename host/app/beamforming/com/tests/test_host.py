"""Offline regression: real protocol emulator, failures, stop/resume and GUI."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from contextlib import closing

APP = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(APP))
import backend as core
import worker
from m512_active14_scan import Emulated512Socket


class HostTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='host_test_',dir=APP/'validation')
        self.path=Path(self.temp.name)
        assert self.path.resolve().is_relative_to((APP/'validation').resolve())
        self.plan=core.RELEASE/'actual11_plan14_v2'
    def tearDown(self):
        assert self.path.resolve().is_relative_to((APP/'validation').resolve())
        self.temp.cleanup()
    def request(self, name='result'):
        return dict(mode='emulator',plan_directory=str(self.plan), result_directory=str(self.path/name),
                    stop_file=str(self.path/'stop'), owner_pid=os.getpid(),resume=False)

    def test_capture_rejects_incomplete_or_duplicate_files(self):
        folder=core.BASE/'M/20260617_160000'
        info=core.validate_capture(folder)
        self.assertEqual(info['channels'],16)
        self.assertEqual(info['capture'],'20260617_160000')
        with self.assertRaises(ValueError):core.validate_capture(folder,info['files'][:15])
        with self.assertRaises(ValueError):core.validate_capture(folder,info['files'][:15]+[info['files'][0]])
        with self.assertRaises(ValueError):core.validate_capture(self.path)

    def test_emulator_exact_progress_and_source_labels(self):
        events=[]
        with patch.object(worker,'emit',lambda kind,**kw:events.append(dict(kind=kind,**kw))), patch('socket.socket',side_effect=AssertionError('Emulator opened a real socket')):
            result=worker.run_scan(self.request())
        self.assertEqual(result['status'],'COMPLETE')
        self.assertEqual(result['verified'],9)
        last=[event for event in events if event['kind']=='progress'][-1]
        self.assertEqual((last['completed'],last['total']),(9,9))
        self.assertEqual((last['tx_packets'],last['rx_packets']),(9*33,9*49))
        data=core.load_result(self.path/'result')
        self.assertEqual(data.summary['source'],'emulator')
        self.assertEqual(int(data.complete.sum()),9)
        figure=core.make_figure(data)
        grid=figure.axes[0].collections[0].get_array()
        self.assertGreater(grid.size,9)
        self.assertEqual(int(grid.count()),9)  # Sampled plan leaves gray gaps, no filled-in bins.
        core.export_figures(data.path)
        self.assertTrue((data.path/'blue_figures/comparison_common.png').exists())

    def test_stop_commits_one_frame_then_resume_without_duplication(self):
        request=self.request()
        stop=lambda count:Path(request['stop_file']).touch() if count==1 else None
        with patch.object(worker,'emit',lambda *a,**kw:None):
            result=worker.run_scan(request,after_frame=stop)
        self.assertEqual(result['status'],'CANCELLED')
        self.assertEqual(result['verified'],1)
        partial=core.load_result(self.path/'result')
        self.assertEqual(partial.summary['status'],'PARTIAL_EMULATOR')
        self.assertEqual(int(partial.complete.sum()),1)
        Path(request['stop_file']).unlink()
        request['resume']=True
        with patch.object(worker,'emit',lambda *a,**kw:None):
            done=worker.run_scan(request)
        self.assertEqual(done['verified'],9)
        import sqlite3
        with closing(sqlite3.connect(self.path/'result/scan.sqlite3')) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM attempts').fetchone()[0],9)
            self.assertEqual(db.execute('SELECT count(*) FROM results').fetchone()[0],9)

    def test_wrong_packet_is_rejected_and_never_committed(self):
        class BadSocket(Emulated512Socket):
            def recv(self,size):
                data=super().recv(size)
                return data[:-1]+bytes([data[-1]^1])
        with patch.object(worker,'emit',lambda *a,**kw:None):
            with self.assertRaises(ValueError):worker.run_scan(self.request(),sock=BadSocket())
        partial=core.load_result(self.path/'result')
        self.assertEqual(int(partial.complete.sum()),0)
        self.assertEqual(partial.summary['source'],'emulator')
        self.assertTrue(partial.summary['run_error'])

    def test_emulator_cannot_be_labelled_hardware(self):
        request=self.request();request['mode']='hardware'
        with self.assertRaisesRegex(ValueError,'模拟器'):
            worker.run_scan(request,sock=Emulated512Socket())
        self.assertFalse((self.path/'result').exists())

    def test_owner_death_requests_stop(self):
        request=self.request()
        self.assertTrue(core.owner_alive(os.getpid()))
        with patch.object(core,'owner_alive',return_value=False):
            self.assertTrue(core.cancelled(request))

    def test_cli_job_does_not_open_network_socket(self):
        request=self.request('cli_result')
        request.update(data_folder=str(core.BASE/'M/20260714_110000'),quick=True)
        path=self.path/'request.json';core.write_json(path,request)
        # A separate worker exercises cache lookup, IPC, export and final outcome.
        result=subprocess.run([str(core.PYTHON),'-E','-X','utf8',str(APP/'worker.py'),'job','--request',str(path)],
                              capture_output=True,text=True,encoding='utf-8',timeout=90,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        outcome=core.read_json(self.path/'outcome.json')
        self.assertEqual(outcome['status'],'COMPLETE')
        self.assertEqual(outcome['network'],dict(restored=True,mutated=False,mode='emulator'))
        self.assertEqual(core.read_json(self.path/'cli_result/scan_summary.json')['source'],'emulator')

    def test_native_widgets_result_tabs_and_screenshot(self):
        import app
        from PIL import ImageGrab
        gui=app.HostApp(auto_load=False)
        gui.settings_file=self.path/'settings.json'
        try:
            gui.geometry('1370x920+30+30')
            existing=core.BASE/'result/M_20260617_160000/M_MVDR512_ACTIVE14_hardware_20261029_194248_2a01d2'
            gui.result_data=core.load_result(existing)
            gui.result_directory=existing
            gui.mode_badge.set('实板回包 · 4838/4838（历史结果）')
            gui.dataset_info.set('2026-06-17 16:00 · 16通道完整\n41频点 · 512周期 · 14路有效')
            gui.draw_charts();gui.update()
            self.assertIn('mvdr',gui.canvases)
            gui.notebook.select(gui.tabs['compare']);gui.update()
            self.assertIn('compare',gui.canvases)
            gui.normalization.set('共同背景');gui.draw_charts();gui.update()
            self.assertEqual(gui.canvases['compare']['key'][1],'common')
            gui.normalization.set('独立背景（结构）');gui.draw_charts();gui.update()
            gui._worker_event(dict(kind='progress',completed=5,total=9,elapsed=5,tx_bytes=1000,rx_bytes=2000,tx_packets=165,rx_packets=245))
            self.assertIn('5 / 9',gui.progress_text.get())
            gui.phase.set('历史结果预览 · 未进行网络传输')
            gui.progress_text.set('4838 / 4838 位置（历史记录）')
            gui.traffic_text.set('当前为历史结果展示；未打开网络连接')
            gui.update()
            self.assertGreater(gui.tabs['compare'].winfo_height(),300)
            bbox=(gui.winfo_rootx(),gui.winfo_rooty(),gui.winfo_rootx()+gui.winfo_width(),gui.winfo_rooty()+gui.winfo_height())
            gui.figures['compare'].savefig(APP/'validation/plot_preview.png',dpi=150,facecolor='white')
            capture=dict(available=True,widget_checks_passed=True)
            try:ImageGrab.grab(bbox=bbox).save(APP/'validation/gui_preview.png')
            except OSError as exc:capture.update(available=False,reason=str(exc))
            core.write_json(APP/'validation/gui_capture.json',capture)
            core.write_json(APP/'validation/gui_layout.json',dict(window=[gui.winfo_width(),gui.winfo_height()],
                plot=[gui.tabs['compare'].winfo_width(),gui.tabs['compare'].winfo_height()],
                sidebar_scroll_region=gui.side_canvas.cget('scrollregion'),native_widgets_passed=True))
        finally:
            gui.destroy()

    def test_gui_offline_button_runs_full_pipeline(self):
        import app
        import time
        gui=app.HostApp(auto_load=False)
        gui.settings_file=self.path/'settings.json'
        try:
            gui.data_path.set(str(core.BASE/'M/20260714_110000'))
            gui.result_root.set(str(self.path/'gui_results'))
            gui.quick.set(True)
            button=next(w for w in gui.controls if isinstance(w,app.ttk.Button) and w.cget('text')=='离线自测')
            button.invoke()
            self.assertTrue(gui.busy)
            deadline=time.monotonic()+90
            while time.monotonic()<deadline and (gui.busy or gui.result_data is None):
                gui.update();time.sleep(.03)
            self.assertFalse(gui.busy,'GUI job timeout')
            self.assertIsNotNone(gui.result_data)
            self.assertEqual(gui.result_data.summary['source'],'emulator')
            self.assertIn('离线模拟',gui.mode_badge.get())
            self.assertIn('100.0%',gui.progress_text.get())
            self.assertTrue((gui.result_directory/'blue_figures/mvdr_blue.png').exists())
            self.assertTrue(core.read_json(gui.request_file.parent/'outcome.json')['network']['restored'])
        finally:
            if gui.busy:
                gui.stop()
                deadline=time.monotonic()+30
                while gui.busy and time.monotonic()<deadline:gui.update();time.sleep(.05)
            gui.destroy()


if __name__=='__main__':
    (APP/'validation').mkdir(exist_ok=True)
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(HostTests)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    core.write_json(APP/'validation/python_tests.json',dict(passed=result.wasSuccessful(),tests=result.testsRun,
        failures=len(result.failures),errors=len(result.errors),actual_hardware_test=False,
        real_adapter_changes=False,production_sources_changed=False))
    raise SystemExit(0 if result.wasSuccessful() else 1)
