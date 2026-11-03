"""Actual-reference M32 entry point; legacy plans are rejected. Check defaults offline."""
from pathlib import Path
from contextlib import closing
import argparse
import json
import socket
import sqlite3
import time
from m_reference_batch_plan import ReferenceScanPlan
from m_reference_batch_release import check_reference_release
from m_batch_scan import scan,EmulatedSocket
from m_batch_result import audit_rows


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    check=sub.add_parser('check');check.add_argument('--plan',type=Path,required=True)
    check.add_argument('--report',type=Path);check.add_argument('--resume-output',type=Path)
    run=sub.add_parser('run');run.add_argument('--plan',type=Path,required=True)
    run.add_argument('--output',type=Path,required=True);run.add_argument('--resume',action='store_true')
    transport=run.add_mutually_exclusive_group(required=True)
    transport.add_argument('--host',choices=['192.0.2.1']);transport.add_argument('--emulate',action='store_true')
    run.add_argument('--timeout',type=float,default=3);run.add_argument('--limit',type=int)
    a=p.parse_args();plan=ReferenceScanPlan(a.plan);release=check_reference_release(plan)
    if a.command=='check':
        if a.resume_output:
            db_path=(a.resume_output/'scan.sqlite3').resolve()
            with closing(sqlite3.connect('file:'+db_path.as_posix()+'?mode=ro',uri=True)) as db:
                db.row_factory=sqlite3.Row;identity=dict(db.execute('SELECT key,value FROM metadata'))
                if identity.get('plan_sha256')!=plan.hash or identity.get('mode')!='hardware':
                    raise ValueError('resume requires this corrected-input hardware plan')
                audit_rows(db,plan)
        report=dict(status='PASS_HF_M32_PLAN_OFFLINE',plan_sha256=plan.hash,frames=plan.meta['frames'],
            preprocessing=plan.meta['preprocessing'],frequencies=plan.nf,lags=plan.nl,blocks=plan.nb,
            reference_code_sha256=plan.meta['reference_files_sha256']['m255a.mat'],
            no_network_traffic=True,release=release)
        if a.report:a.report.write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(f'PASS HF_M32_PREFLIGHT: actual m255a; {plan.meta["frames"]} frames; no hardware traffic')
        return
    if not 0<a.timeout<=60 or (a.limit is not None and a.limit<1):raise ValueError('invalid timeout/limit')
    if a.emulate:
        scan(plan,a.output,EmulatedSocket(),'emulator',a.resume,limit=a.limit)
    else:
        if a.resume:time.sleep(.1)
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            sock.settimeout(a.timeout);sock.bind(('192.0.2.2',5000));sock.connect((a.host,5000))
            scan(plan,a.output,sock,'hardware',a.resume,limit=a.limit)


if __name__=='__main__':main()
