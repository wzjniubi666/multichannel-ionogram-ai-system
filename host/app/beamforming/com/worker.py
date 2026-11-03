"""Isolated, cancellable desktop worker; no network traffic in emulator mode."""
from pathlib import Path
import argparse
import contextlib
import json
import os
import secrets
import socket
import subprocess
import sys
import time
import traceback
import backend as core
from live_preview import metadata, committed_pixel, relay_process


def emit(kind, **fields):
    print('GUI_EVENT ' + json.dumps(dict(kind=kind, **fields), ensure_ascii=False), flush=True)


class PreparationOutput:
    def __init__(self, original, request):
        self.original, self.request, self.pending = original, request, ''
    def write(self, value):
        self.original.write(value); self.original.flush()
        self.pending += value
        if '\n' in self.pending:
            self.pending = self.pending.rsplit('\n', 1)[-1]
            core.check_cancel(self.request)
        return len(value)
    def flush(self):
        self.original.flush()


class CountingSocket:
    def __init__(self, sock, total, completed=0):
        self.sock, self.total, self.completed = sock, total, completed
        self.tx_bytes = self.rx_bytes = self.tx_packets = self.rx_packets = 0
        self.started, self.last = time.monotonic(), 0.
    def select(self, *args):
        if hasattr(self.sock, 'select'):
            self.sock.select(*args)
    def send(self, data):
        sent = self.sock.send(data)
        if sent != len(data):
            raise OSError('UDP数据报未完整发送')
        self.tx_bytes += sent; self.tx_packets += 1
        self.report()
        return sent
    def recv(self, size):
        value = self.sock.recv(size)
        self.rx_bytes += len(value); self.rx_packets += 1
        self.report()
        return value
    def report(self, force=False):
        now = time.monotonic()
        if force or now-self.last >= .2:
            emit('progress', completed=self.completed, total=self.total, elapsed=now-self.started,
                 tx_bytes=self.tx_bytes, rx_bytes=self.rx_bytes, tx_packets=self.tx_packets, rx_packets=self.rx_packets)
            self.last = now


def run_scan(request, sock=None, after_frame=None):
    from m512_active14_scan import Journal512, TraceSocket, audit_rows, expected_received, Emulated512Socket, unpack_packets
    from m512_packets import requests
    from udp512 import exchange, decode, RESULT
    from m512_active14_result import aggregate
    mode = request['mode']
    if mode not in ('hardware', 'emulator'):
        raise ValueError('Invalid data source mode')
    plan = core.verify_plan(request['plan_directory'])
    if mode == 'hardware' and isinstance(sock, Emulated512Socket):
        raise ValueError('模拟器不能标记为实板结果')
    if sock is None:
        if mode == 'emulator':
            sock = Emulated512Socket()
        else:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024*1024)
            sock.settimeout(3)
            sock.bind(('192.0.2.2', 5000)); sock.connect(('192.0.2.1', 5000))
    journal = Journal512(request['result_directory'], plan, mode, request.get('resume', False))
    counting = CountingSocket(sock, plan.meta['frames'], len(journal.completed))
    failure = None; stopped = False; nonce = secrets.randbits(32)
    try:
        emit('stage', name='校验断点记录' if request.get('resume') else '传输与波束合成', detail=mode)
        previous=audit_rows(journal.db, plan)
        retained=[]
        for row in previous:
            packets=[decode(raw) for raw in unpack_packets(row['received'])]
            retained.append(committed_pixel(plan,row['ordinal'],[p for p in packets if p.kind==RESULT]))
        emit('preview', **metadata(plan,request['result_directory'],mode), pixels=retained)
        counting.report(True)
        for ordinal in range(plan.meta['frames']):
            if ordinal in journal.completed:
                continue
            if core.cancelled(request):
                stopped = True; break
            cfg, iq, expected = requests(plan, ordinal, nonce)
            counting.select(cfg, iq, expected)
            attempt = journal.begin(ordinal, nonce, cfg, iq, expected)
            trace = TraceSocket(counting); start = time.monotonic()
            try:
                received = exchange(trace, cfg, iq)
                if received != expected or trace.received != expected_received(cfg, iq, expected):
                    raise ValueError('回包与定点参考不一致，已停止且未自动重试')
            except BaseException as exc:
                journal.finish(attempt, ordinal, trace, time.monotonic()-start, exc)
                raise
            journal.finish(attempt, ordinal, trace, time.monotonic()-start)
            counting.completed = len(journal.completed)
            # Journal.finish commits before either the progress count or pixel is published.
            counting.report(force=True)
            emit('pixel',path=request['result_directory'],**committed_pixel(plan,ordinal,received))
            if after_frame:
                after_frame(counting.completed)
    except BaseException as exc:
        failure = exc
    finally:
        counting.report(True)
        if hasattr(sock, 'close'):
            sock.close()
        try:
            emit('stage', name='校验并保存已完成结果', detail='完成后自动生成蓝底图')
            summary = aggregate(journal.db, plan, request['result_directory'], mode, render=False,
                                error=str(failure) if failure else ('USER_STOP' if stopped else None))
        finally:
            journal.close()
        emit('result', path=request['result_directory'], status=summary['status'], verified=summary['verified_frames'])
    if failure:
        raise failure
    return dict(status='CANCELLED' if stopped else 'COMPLETE', verified=summary['verified_frames'], mode=mode)


def run_job(request, request_path):
    if request['mode'] not in ('hardware', 'emulator'):
        raise ValueError('Unknown mode')
    if request['mode'] == 'hardware' and not core.is_admin():
        raise PermissionError('请双击管理员启动入口后开始实板合成')
    if request.get('resume'):
        previous = core.read_json(Path(request['result_directory'])/'scan_summary.json')
        if previous['source'] != request['mode'] or previous['status'].startswith('COMPLETE_'):
            raise ValueError('请选择来源相同且未完成的结果目录')
        request['plan_directory'] = previous['plan_directory']
        plan = core.verify_plan(request['plan_directory'])
        if previous['plan_sha256'] != plan.hash:
            raise ValueError('断点计划不匹配')
    else:
        emit('stage', name='检查16通道数据', detail=request['data_folder'])
        core.validate_capture(request['data_folder'])
        core.check_cancel(request)
        plan = core.find_plan(request['data_folder'], request.get('quick', False), request, emit)
        if plan is None:
            from m512_active14_plan import prepare
            target = core.APP/'plans'/(Path(request['data_folder']).name+'_'+core.stamp())
            emit('stage', name='准备数据与定点参考', detail=str(target))
            with contextlib.redirect_stdout(PreparationOutput(sys.stdout, request)):
                prepare(Path(request['data_folder']), target, core.REFERENCE,
                        frequencies=[7.5, 10., 15.] if request.get('quick') else None,
                        lags=[20,148,244] if request.get('quick') else None)
            plan = core.verify_plan(target)
        request['plan_directory'] = str(plan.path)
    core.write_json(request_path, request)
    emit('plan', path=str(plan.path), total=plan.meta['frames'])
    core.check_cancel(request)
    Path(request['result_directory']).parent.mkdir(parents=True, exist_ok=True)
    if request['mode'] == 'emulator':
        result = run_scan(request)
        network = dict(restored=True, mutated=False, mode='emulator')
    else:
        emit('stage', name='配置专用网卡', detail='原设置将自动备份，并在结束后恢复')
        command = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                   '-File', str(core.APP/'network_session.ps1'), '-RequestFile', str(request_path)]
        code = relay_process(command)
        network_path = request_path.parent/'network_result.json'
        if not network_path.exists():
            raise RuntimeError('网络会话异常退出，请查看日志并使用“恢复网卡”')
        network = core.read_json(network_path)
        emit('network', **network)
        if not network.get('restored'):
            raise RuntimeError('网卡恢复未通过校验，请使用“恢复网卡”，备份：'+network.get('backup_directory', ''))
        worker_result = request_path.parent/'scan_worker_result.json'
        if code or not worker_result.exists():
            if not worker_result.exists() and core.cancelled(request):
                result=dict(status='CANCELLED',verified=0,mode='hardware')
            else:
                raise RuntimeError(network.get('error') or '通信失败，已保留已完成结果；网卡已恢复')
        else:
            result = core.read_json(worker_result)
    if (Path(request['result_directory'])/'scan_results.npz').exists():
        emit('stage', name='生成蓝底电离图', detail='单通道、实板结果及统一背景对照')
        core.export_figures(request['result_directory'])
    return dict(**result, result_directory=request['result_directory'], network=network)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['job', 'scan', 'preflight'])
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    request = core.read_json(args.request)
    outcome_file = args.request.parent/('scan_worker_result.json' if args.command == 'scan' else 'outcome.json')
    try:
        if args.command == 'preflight':
            core.verify_plan(request['plan_directory'])
            core.check_cancel(request)
            return
        result = run_scan(request) if args.command == 'scan' else run_job(request, args.request)
        core.write_json(outcome_file, result)
        emit('done', scope=args.command, **result)
    except core.Cancelled as exc:
        result = dict(status='CANCELLED', message=str(exc))
        core.write_json(outcome_file, result); emit('done', scope=args.command, **result)
        if args.command == 'preflight':
            raise SystemExit(2)
    except BaseException as exc:
        traceback.print_exc()
        result = dict(status='FAILED', error=str(exc), result_directory=request.get('result_directory'))
        core.write_json(outcome_file, result); emit('error', scope=args.command, **result)
        raise SystemExit(1)


if __name__ == '__main__':
    main()
