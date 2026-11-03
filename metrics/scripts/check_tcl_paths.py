"""Tcl completeness and moved input-path checks, without invoking Vivado commands."""
from pathlib import Path
import json,os
ROOT=Path(__file__).resolve().parents[2]
os.environ['TCL_LIBRARY']=str(ROOT/'host/app/beamforming/com/runtime/tcl/tcl8.6')
import tkinter
interp=tkinter.Tcl()
scripts=['fpga/build/beamforming/build.tcl','fpga/build/beamforming/create_project.tcl',
         'fpga/build/recognition/build.tcl','fpga/build/recognition/diagnose.tcl','fpga/build/recognition/view_floorplan.tcl']
for name in scripts:
    assert interp.call('info','complete',(ROOT/name).read_text(encoding='utf-8-sig')),name
inputs=['fpga/src/beamforming/release_sources/kt325t_network512_board_top.v',
        'fpga/src/beamforming/release_constraints/kt325t_network_board.xdc',
        'fpga/build/beamforming/original/tools/implement_m512_board.tcl',
        'fpga/src/recognition/rtl/udp_mdio_bridge.v','fpga/src/recognition/constraints/board.xdc',
        'fpga/build/recognition/board_case/udp_mdio_bridge.bit','fpga/build/recognition/board_case/udp_mdio_bridge.ltx',
        'fpga/build/recognition/board_case/udp_mdio_bridge.dcp','fpga/build/recognition/board_case/manifest.json']
for name in inputs:assert (ROOT/name).is_file(),name
for sub in ('beamforming','recognition'):
    script=ROOT/f'fpga/build/{sub}/build.tcl'
    assert script.parent.parents[2]==ROOT
output=ROOT/'metrics/logs/integration/tcl_paths.json'
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(dict(passed=True,tcl_version=interp.call('info','patchlevel'),
    syntax_complete_scripts=len(scripts),existing_build_inputs=len(inputs),vivado_executed=False,fpga_programmed=False),indent=2)+'\n',encoding='utf-8')
print('PASS TCL COMPLETENESS / PATHS:5 scripts,9 inputs; no Vivado commands executed.')
