from pathlib import Path
import argparse,json,os,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
def vivado():
    settings=json.loads((ROOT/'host/deploy/recognition/settings.json').read_text(encoding='utf-8'))
    exe=os.environ.get('VIVADO_EXECUTABLE') or settings.get('vivado_executable') or shutil.which('vivado.bat') or shutil.which('vivado')
    if not exe or not Path(exe).is_file():raise SystemExit('Vivado not found. Set vivado_executable in settings.json, or VIVADO_EXECUTABLE, or use a Vivado command prompt.')
    return str(exe)
def main():
    p=argparse.ArgumentParser();p.add_argument('--floorplan',action='store_true');p.add_argument('--check',action='store_true');a=p.parse_args()
    subprocess.run([sys.executable,str(ROOT/'host/app/recognition/check_project.py')],cwd=ROOT,check=True)
    if a.check:return
    exe=vivado()
    if a.floorplan:
        subprocess.run([exe,'-mode','gui','-source',str(ROOT/'fpga/build/recognition/view_floorplan.tcl'),'-log',str(ROOT/'metrics/logs/recognition/view_floorplan.log'),'-nojournal'],cwd=ROOT,check=True)
        return
    subprocess.run([exe,'-mode','batch','-source',str(ROOT/'fpga/build/recognition/diagnose.tcl'),'-log',str(ROOT/'metrics/logs/recognition/run_board.log'),'-nojournal'],cwd=ROOT,check=True)
    subprocess.run([sys.executable,str(ROOT/'host/app/recognition/test_images.py')],cwd=ROOT,check=True)
if __name__=='__main__':main()
