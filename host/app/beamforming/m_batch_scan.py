"""Stop-and-wait M32 scan, durable packet journal and explicit resume.

Default check is offline. Real traffic requires run --host; --emulate is
separate and all its outputs are labelled non-hardware.
"""
from pathlib import Path
import argparse
import json
import secrets
import socket
import sqlite3
import time
from datetime import datetime,timezone
from m_batch_plan import ScanPlan
from udp_replay import Packet,ACK,RESULT,configuration,iq_packets,exchange,signed_bytes


def requests(plan,ordinal,nonce):
    fp,lp,bp=plan.coordinate(ordinal)
    cid=(nonce+2*ordinal)&0xffffffff;fid=(nonce+2*ordinal+1)&0xffffffff
    cfg=configuration(plan.steering[fp,:,0].tolist(),plan.steering[fp,:,1].tolist(),cid,
        plan.meta['source_frequency_index'][fp],plan.meta['relative_lag_samples'][lp])
    x=plan.iq[ordinal]
    packets=iq_packets(x[:,:,0].reshape(-1).tolist(),x[:,:,1].reshape(-1).tolist(),fid,cid,cfg.frequency_index,cfg.gate_index)
    payload=b''.join(signed_bytes(int(r),48)+signed_bytes(int(i),48) for r,i in plan.expected[ordinal])
    expected=Packet(RESULT,fid,cid,cfg.frequency_index,cfg.gate_index,payload=payload)
    return cfg,packets,expected


class TraceSocket:
    def __init__(self,sock):self.sock=sock;self.sent=[];self.received=[]
    def send(self,data):
        count=self.sock.send(data);self.sent.append(bytes(data));return count
    def recv(self,size):
        data=self.sock.recv(size);self.received.append(bytes(data));return data


class EmulatedSocket:
    """Protocol test transport: known plan reference replies; never real hardware."""
    def select(self,cfg,iq,expected):
        self.expected_sends=[p.encode() for p in [cfg,*iq]];self.position=0
        self.responses=[Packet(ACK,0,cfg.config_id,cfg.frequency_index,cfg.gate_index).encode(),expected.encode()]
    def send(self,data):
        if data!=self.expected_sends[self.position]:raise ValueError('emulated TX mismatch')
        self.position+=1;return len(data)
    def recv(self,size):
        required=1 if len(self.responses)==2 else 3
        if self.position!=required:raise ValueError('emulated handshake ordering')
        return self.responses.pop(0)


class Journal:
    def __init__(self,output,plan,mode,resume=False):
        self.output=Path(output).resolve();self.plan=plan;self.mode=mode
        exists=(self.output/'scan.sqlite3').exists()
        if self.output.exists() and not exists and any(self.output.iterdir()):
            raise FileExistsError('refusing to overwrite a nonempty result directory')
        if exists and not resume:raise FileExistsError('scan exists; use explicit --resume')
        if resume and not exists:raise FileNotFoundError('resume database does not exist')
        self.output.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(self.output/'scan.sqlite3',timeout=.1)
        try:
            self._initialize(plan,mode,exists)
        except BaseException:
            self.db.close()
            raise

    def _initialize(self,plan,mode,exists):
        self.db.row_factory=sqlite3.Row
        self.db.execute('PRAGMA locking_mode=EXCLUSIVE')
        self.db.execute('PRAGMA journal_mode=DELETE')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS attempts(
              id INTEGER PRIMARY KEY AUTOINCREMENT,ordinal INTEGER NOT NULL,
              nonce INTEGER NOT NULL,config_id INTEGER NOT NULL,frame_id INTEGER NOT NULL,
              status TEXT NOT NULL,started_utc TEXT NOT NULL,elapsed_seconds REAL,
              planned_config BLOB NOT NULL,planned_iq0 BLOB NOT NULL,planned_iq1 BLOB NOT NULL,
              received_1 BLOB,received_2 BLOB,sent_count INTEGER NOT NULL DEFAULT 0,error TEXT);
            CREATE TABLE IF NOT EXISTS results(ordinal INTEGER PRIMARY KEY,attempt_id INTEGER UNIQUE NOT NULL,
              FOREIGN KEY(attempt_id) REFERENCES attempts(id));
        ''')
        identity=dict(plan_sha256=plan.hash,mode=mode,protocol='BFM1/1',records_per_frame='32',
                      endpoint='192.0.2.2:5000 -> 192.0.2.1:5000')
        if exists:
            current={r['key']:r['value'] for r in self.db.execute('SELECT * FROM metadata')}
            if any(current.get(k)!=v for k,v in identity.items()):
                raise ValueError('resume plan/mode/endpoint mismatch')
        else:
            self.db.executemany('INSERT INTO metadata VALUES(?,?)',identity.items());self.db.commit()
        self.completed={r[0] for r in self.db.execute('SELECT ordinal FROM results')}

    def begin(self,ordinal,nonce,cfg,packets,expected):
        cur=self.db.execute('''INSERT INTO attempts(ordinal,nonce,config_id,frame_id,status,started_utc,
                planned_config,planned_iq0,planned_iq1) VALUES(?,?,?,?,?,?,?,?,?)''',
            (ordinal,nonce,cfg.config_id,expected.frame_id,'PENDING',datetime.now(timezone.utc).isoformat(),
             cfg.encode(),packets[0].encode(),packets[1].encode()))
        self.db.commit();return cur.lastrowid

    def finish(self,attempt,ordinal,trace,elapsed,error=None):
        status='FAILED' if error else 'VERIFIED'
        raw=trace.received+[None,None]
        with self.db:
            self.db.execute('''UPDATE attempts SET status=?,received_1=?,received_2=?,sent_count=?,
                elapsed_seconds=?,error=? WHERE id=?''',
                (status,raw[0],raw[1],len(trace.sent),elapsed,str(error) if error else None,attempt))
            if not error:self.db.execute('INSERT INTO results VALUES(?,?)',(ordinal,attempt))
        if not error:self.completed.add(ordinal)

    def close(self):self.db.close()


def scan(plan,output,sock,mode='hardware',resume=False,nonce=None,limit=None,render=True):
    if mode not in ('hardware','emulator'):raise ValueError('invalid source mode')
    if mode=='hardware' and isinstance(sock,EmulatedSocket):raise ValueError('emulator cannot be labelled hardware')
    journal=Journal(output,plan,mode,resume)
    nonce=secrets.randbits(32) if nonce is None else nonce
    total=plan.meta['frames'];t0=time.perf_counter();sent=0;failure=None
    try:
        # Re-audit accepted responses before resume, rather than trusting counters.
        from m_batch_result import audit_rows,aggregate
        audit_rows(journal.db,plan)
        for ordinal in range(total):
            if ordinal in journal.completed:continue
            if limit is not None and sent>=limit:break
            cfg,packets,expected=requests(plan,ordinal,nonce)
            if hasattr(sock,'select'):sock.select(cfg,packets,expected)
            attempt=journal.begin(ordinal,nonce,cfg,packets,expected)
            trace=TraceSocket(sock);frame_start=time.perf_counter()
            try:
                actual=exchange(trace,cfg,packets)
                if actual!=expected:raise ValueError(f'BATCH_RESULT_MISMATCH ordinal={ordinal}')
            except BaseException as exc:
                journal.finish(attempt,ordinal,trace,time.perf_counter()-frame_start,exc)
                raise
            journal.finish(attempt,ordinal,trace,time.perf_counter()-frame_start)
            sent+=1
            if sent==1 or sent%50==0 or len(journal.completed)==total:
                fp,lp,bp=plan.coordinate(ordinal)
                print(f'SCAN {len(journal.completed)}/{total}: {plan.meta["frequency_mhz"][fp]:g}MHz '
                    f'lag={plan.meta["relative_lag_samples"][lp]} block={plan.meta["record_starts"][bp]}, '
                    f'elapsed={time.perf_counter()-t0:.1f}s source={mode}',flush=True)
    except BaseException as exc:
        failure=exc
    finally:
        try:
            from m_batch_result import aggregate
            summary=aggregate(journal.db,plan,journal.output,mode,render=render,
                run_error=str(failure) if failure else None)
        finally:journal.close()
    if failure:raise failure
    print(f'PASS SCAN_SAVED: {summary["status"]}, {summary["verified_frames"]}/{total} frames, {output}')
    return summary


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    c=sub.add_parser('check');c.add_argument('--plan',type=Path,required=True)
    c.add_argument('--report',type=Path)
    c.add_argument('--resume-output',type=Path)
    r=sub.add_parser('run');r.add_argument('--plan',type=Path,required=True)
    r.add_argument('--output',type=Path,required=True);r.add_argument('--resume',action='store_true')
    choice=r.add_mutually_exclusive_group(required=True)
    choice.add_argument('--host',choices=['192.0.2.1']);choice.add_argument('--emulate',action='store_true')
    r.add_argument('--timeout',type=float,default=3);r.add_argument('--limit',type=int)
    args=p.parse_args();plan=ScanPlan(args.plan)
    from m_batch_release import check_batch_release
    release=check_batch_release(plan)
    if args.command=='check':
        if args.resume_output:
            from contextlib import closing
            path=(args.resume_output/'scan.sqlite3').resolve()
            with closing(sqlite3.connect('file:'+path.as_posix()+'?mode=ro',uri=True)) as db:
                db.row_factory=sqlite3.Row
                current=dict(db.execute('SELECT key,value FROM metadata'))
                if current.get('plan_sha256')!=plan.hash or current.get('mode')!='hardware':
                    raise ValueError('resume output is not this hardware scan plan')
                from m_batch_result import audit_rows
                audit_rows(db,plan)
        report=dict(status='PASS_PLAN_OFFLINE',plan_sha256=plan.hash,frames=plan.meta['frames'],
                    frequencies=plan.nf,lags=plan.nl,blocks=plan.nb,no_network_traffic=True,release=release)
        if args.report:args.report.write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(f'PASS M_BATCH_PLAN: M data, {plan.nf} frequencies x {plan.nl} lags x {plan.nb} blocks '
              f'= {plan.meta["frames"]} frames; 32 records/frame; no network traffic')
        return
    if not 0<args.timeout<=60 or (args.limit is not None and args.limit<1):raise ValueError('invalid timeout/limit')
    if args.emulate:
        scan(plan,args.output,EmulatedSocket(),'emulator',args.resume,limit=args.limit)
    else:
        if args.resume:time.sleep(.1)  # Existing image assembly/core timeout <=10ms; explicit recovery guard.
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            sock.settimeout(args.timeout);sock.bind(('192.0.2.2',5000));sock.connect((args.host,5000))
            scan(plan,args.output,sock,'hardware',args.resume,limit=args.limit)


if __name__=='__main__':main()
