"""Durable joint512 stop-and-wait scan; emulator and real hardware are explicitly separate."""
from pathlib import Path
from contextlib import closing
from datetime import datetime,timezone
import argparse
import json
import secrets
import socket
import sqlite3
import struct
import time
from m512_plan import Plan512
from m512_packets import requests
from udp512 import Packet512,ACK,IQ_ACK,decode,exchange


def pack_packets(packets):
    return b''.join(struct.pack('!I',len(packet))+packet for packet in packets)


def unpack_packets(data):
    result=[];offset=0
    while offset<len(data):
        if len(data)-offset<4:raise ValueError('truncated packet-list length')
        size=struct.unpack_from('!I',data,offset)[0];offset+=4
        if size>1056 or size<32 or offset+size>len(data):raise ValueError('invalid packet-list bounds')
        result.append(data[offset:offset+size]);offset+=size
    return result


def expected_received(cfg,iq,results):
    return [Packet512(ACK,0,cfg.config_id,cfg.frequency_index,cfg.gate_index).encode()]+[
        Packet512(IQ_ACK,iq[0].frame_id,cfg.config_id,cfg.frequency_index,cfg.gate_index,index,32).encode() for index in range(32)]+[
        packet.encode() for packet in results]


class TraceSocket:
    def __init__(self,sock):self.sock=sock;self.sent=[];self.received=[]
    def send(self,data):
        result=self.sock.send(data);self.sent.append(bytes(data));return result
    def recv(self,size):
        data=self.sock.recv(size);self.received.append(bytes(data));return data


class Emulated512Socket:
    """Test-only expected-packet transport, never measurements."""
    def select(self,cfg,iq,results):
        self.expected_sends=[packet.encode() for packet in (cfg,*iq)];self.position=0
        self.responses=expected_received(cfg,iq,results)
    def send(self,data):
        if data!=self.expected_sends[self.position]:raise ValueError('512 emulator TX mismatch')
        self.position+=1;return len(data)
    def recv(self,size):
        if self.position!=min(50-len(self.responses),33):raise ValueError('512 IQ-ACK ordering violation')
        return self.responses.pop(0)


class Journal512:
    def __init__(self,output,plan,mode,resume=False):
        self.output=Path(output).resolve();self.plan=plan;self.mode=mode
        exists=(self.output/'scan.sqlite3').exists()
        if self.output.exists() and not exists and any(self.output.iterdir()):raise FileExistsError('nonempty512 result directory')
        if exists and not resume:raise FileExistsError('512 result exists; resume must be explicit')
        if resume and not exists:raise FileNotFoundError('512 resume database missing')
        self.output.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(self.output/'scan.sqlite3',timeout=.1)
        try:
            self.db.row_factory=sqlite3.Row
            self.db.execute('PRAGMA locking_mode=EXCLUSIVE');self.db.execute('PRAGMA journal_mode=DELETE');self.db.execute('PRAGMA synchronous=FULL')
            self.db.executescript('''
                CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS attempts(id INTEGER PRIMARY KEY AUTOINCREMENT,ordinal INTEGER NOT NULL,
                    nonce INTEGER NOT NULL,status TEXT NOT NULL,started_utc TEXT NOT NULL,elapsed_seconds REAL,
                    planned_config BLOB NOT NULL,planned_iq BLOB NOT NULL,planned_result BLOB NOT NULL,
                    received BLOB,sent_count INTEGER NOT NULL DEFAULT 0,error TEXT);
                CREATE TABLE IF NOT EXISTS results(ordinal INTEGER PRIMARY KEY,attempt_id INTEGER UNIQUE NOT NULL,
                    FOREIGN KEY(attempt_id) REFERENCES attempts(id));
            ''')
            identity=dict(plan_sha256=plan.hash,mode=mode,protocol='BFM1/2',records_per_frame='512',endpoint='192.0.2.2:5000 -> 192.0.2.1:5000')
            if exists:
                current=dict(self.db.execute('SELECT key,value FROM metadata'))
                if any(current.get(key)!=value for key,value in identity.items()):raise ValueError('512 resume plan/mode/endpoint mismatch')
            else:self.db.executemany('INSERT INTO metadata VALUES(?,?)',identity.items());self.db.commit()
            self.completed={row[0] for row in self.db.execute('SELECT ordinal FROM results')}
        except BaseException:self.db.close();raise

    def begin(self,ordinal,nonce,cfg,iq,expected):
        cursor=self.db.execute('INSERT INTO attempts(ordinal,nonce,status,started_utc,planned_config,planned_iq,planned_result) VALUES(?,?,?,?,?,?,?)',
            (ordinal,nonce,'PENDING',datetime.now(timezone.utc).isoformat(),cfg.encode(),pack_packets([p.encode() for p in iq]),pack_packets([p.encode() for p in expected])))
        self.db.commit();return cursor.lastrowid

    def finish(self,attempt,ordinal,trace,elapsed,error=None):
        self.db.execute('UPDATE attempts SET status=?,elapsed_seconds=?,received=?,sent_count=?,error=? WHERE id=?',
            ('FAILED' if error else 'VERIFIED',elapsed,pack_packets(trace.received),len(trace.sent),str(error) if error else None,attempt))
        if error is None:self.db.execute('INSERT INTO results VALUES(?,?)',(ordinal,attempt))
        self.db.commit()
        if error is None:self.completed.add(ordinal)

    def close(self):self.db.close()


def audit_rows(db,plan):
    rows=list(db.execute('SELECT r.ordinal AS accepted_ordinal,a.* FROM results r JOIN attempts a ON a.id=r.attempt_id ORDER BY r.ordinal'))
    seen=set()
    for row in rows:
        ordinal=row['ordinal']
        if ordinal!=row['accepted_ordinal'] or ordinal in seen or row['status']!='VERIFIED' or row['sent_count']!=33:
            raise ValueError('512 persisted result ownership/status mismatch')
        seen.add(ordinal);cfg,iq,result=requests(plan,ordinal,row['nonce'])
        if (row['planned_config']!=cfg.encode() or unpack_packets(row['planned_iq'])!=[p.encode() for p in iq]
                or unpack_packets(row['planned_result'])!=[p.encode() for p in result]
                or unpack_packets(row['received'])!=expected_received(cfg,iq,result)):
            raise ValueError('512 saved packet mismatch')
    return rows


def scan(plan,output,sock,mode='hardware',resume=False,nonce=None,limit=None,render=True):
    if mode not in ('hardware','emulator'):raise ValueError('invalid512 mode')
    if mode=='hardware' and isinstance(sock,Emulated512Socket):raise ValueError('emulator cannot be labelled512 hardware')
    journal=Journal512(output,plan,mode,resume)
    nonce=secrets.randbits(32) if nonce is None else nonce
    sent=0;failure=None;t0=time.perf_counter()
    try:
        audit_rows(journal.db,plan)
        for ordinal in range(plan.meta['frames']):
            if ordinal in journal.completed:continue
            if limit is not None and sent>=limit:break
            cfg,iq,wanted=requests(plan,ordinal,nonce)
            if hasattr(sock,'select'):sock.select(cfg,iq,wanted)
            attempt=journal.begin(ordinal,nonce,cfg,iq,wanted);trace=TraceSocket(sock);start=time.perf_counter()
            try:
                received=exchange(trace,cfg,iq)
                if received!=wanted or trace.received!=expected_received(cfg,iq,wanted):raise ValueError('512 result differs from fixed reference')
            except BaseException as exc:
                journal.finish(attempt,ordinal,trace,time.perf_counter()-start,exc);raise
            journal.finish(attempt,ordinal,trace,time.perf_counter()-start)
            sent+=1
            if sent==1 or sent%50==0 or len(journal.completed)==plan.meta['frames']:
                fp,lp,_=plan.coordinate(ordinal)
                print(f'SCAN512 {len(journal.completed)}/{plan.meta["frames"]}: {plan.meta["frequency_mhz"][fp]:g}MHz lag={plan.meta["relative_lag_samples"][lp]}, elapsed={time.perf_counter()-t0:.1f}s source={mode}',flush=True)
    except BaseException as exc:failure=exc
    finally:
        try:
            from m512_result import aggregate
            summary=aggregate(journal.db,plan,journal.output,mode,render,str(failure) if failure else None)
        finally:journal.close()
    if failure:raise failure
    print(f'PASS SCAN512_SAVED: {summary["status"]}, {summary["verified_frames"]}/{plan.meta["frames"]} frames, {output}')
    return summary


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='command',required=True)
    check=sub.add_parser('check');check.add_argument('--plan',type=Path,required=True);check.add_argument('--report',type=Path);check.add_argument('--resume-output',type=Path)
    run=sub.add_parser('run');run.add_argument('--plan',type=Path,required=True);run.add_argument('--output',type=Path,required=True);run.add_argument('--resume',action='store_true')
    choice=run.add_mutually_exclusive_group(required=True);choice.add_argument('--host',choices=['192.0.2.1']);choice.add_argument('--emulate',action='store_true')
    run.add_argument('--timeout',type=float,default=3);run.add_argument('--limit',type=int)
    a=p.parse_args();plan=Plan512(a.plan)
    from m512_release import check_release
    release=check_release(plan)
    if a.command=='check':
        if a.resume_output:
            with closing(sqlite3.connect('file:'+(a.resume_output/'scan.sqlite3').resolve().as_posix()+'?mode=ro',uri=True)) as db:
                db.row_factory=sqlite3.Row;identity=dict(db.execute('SELECT key,value FROM metadata'))
                if identity.get('plan_sha256')!=plan.hash or identity.get('mode')!='hardware':raise ValueError('not this joint512 hardware result')
                audit_rows(db,plan)
        report=dict(status='PASS_JOINT512_PREFLIGHT',plan_sha256=plan.hash,frames=plan.meta['frames'],no_network_traffic=True,release=release)
        if a.report:a.report.write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(f'PASS M512_PLAN: {plan.meta["frames"]} locations, one weight set per512 periods; no traffic');return
    if not 0<a.timeout<=60 or(a.limit is not None and a.limit<1):raise ValueError('invalid timeout/limit')
    if a.emulate:scan(plan,a.output,Emulated512Socket(),'emulator',a.resume,limit=a.limit)
    else:
        if a.resume:time.sleep(.25)
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024*1024)
            sock.settimeout(a.timeout);sock.bind(('192.0.2.2',5000));sock.connect((a.host,5000))
            scan(plan,a.output,sock,'hardware',a.resume,limit=a.limit)


if __name__=='__main__':main()
