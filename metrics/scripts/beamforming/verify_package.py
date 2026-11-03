"""Portable, offline archive and ACTIVE14 reference replay. No network/hardware writes."""
from pathlib import Path
from dataclasses import replace
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
import hashlib
import json
import platform
import sys
import traceback

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT/'host/app/beamforming'))


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024*1024), b''):
            h.update(block)
    return h.hexdigest().upper()


def require(value, message):
    if not value:
        raise AssertionError(message)


def main():
    try:
        now = datetime.now(ZoneInfo('Asia/Shanghai'))
    except ZoneInfoNotFoundError:
        from datetime import timezone, timedelta
        now = datetime.now(timezone(timedelta(hours=8)))
    tag = now.strftime('%Y%m%d_%H%M%S_%f')
    logdir = ROOT/'metrics/logs/beamforming'
    logdir.mkdir(parents=True, exist_ok=True)
    log = []
    result = dict(started_at=now.isoformat(), timezone='Asia/Shanghai',
                  python=sys.version, executable=sys.executable,
                  platform=platform.platform(), scope='OFFLINE_PACKAGE_AND_INTEGER_REFERENCE',
                  new_rtl_simulation=False, new_synthesis=False, new_implementation=False,
                  hardware_programmed=False, network_traffic=False, checks=[])

    def report(name, **details):
        result['checks'].append(dict(name=name, status='PASS', **details))
        line = name+' PASS '+json.dumps(details, ensure_ascii=False)
        log.append(line)
        print(line, flush=True)

    try:
        manifest = json.loads((ROOT/'report/package_manifest.json').read_text(encoding='utf-8'))
        for row in manifest['files']:
            p = ROOT/row['path']
            require(p.is_file(), f'Missing file: {p}')
            require(p.stat().st_size == row['bytes'], f'Size mismatch: {p}')
            require(digest(p) == row['sha256'], f'SHA256 mismatch: {p}')
        report('archive_integrity', files=len(manifest['files']))
        provenance = json.loads((ROOT/'report/source_manifest.json').read_text(encoding='utf-8'))
        for row in provenance['files']:
            require(digest(ROOT/row['destination']) == row['sha256'],
                    'Copied file differs from original identity: '+row['destination'])
        report('copied_source_identity', files=len(provenance['files']))

        import numpy as np
        import scipy
        import matplotlib
        from m_reference_preprocess import load_reference
        from mvdr_fixed_reference import solve_fixed, beam_fixed
        from udp512 import (configuration, iq_packets, result_packets, decode,
                            beam_values, exchange, Packet512, ACK, IQ_ACK)
        result['dependencies'] = {m.__name__: m.__version__ for m in (np,scipy,matplotlib)}
        try:
            import threadpoolctl
            result['dependencies']['threadpoolctl']=threadpoolctl.__version__
        except ImportError:
            result['dependencies']['threadpoolctl']='not installed; optional thread limiter only'

        plan = ROOT/'metrics/evidence/beamforming/active14_smoke_plan'
        code = load_reference(ROOT/'host/model/beamforming/HFceshi/m255a.mat')
        np.testing.assert_array_equal(code, np.load(plan/'reference_code.npy'))
        report('actual_M255_code', chips=255, values=[-1,1])
        iq = np.load(plan/'iq.npy')
        weights = np.load(plan/'expected_weights.npy')
        expected = np.load(plan/'expected_beam.npy')
        steering = np.load(plan/'steering.npy')
        gains = np.load(plan/'gains.npy')
        meta = json.loads((plan/'plan.json').read_text(encoding='utf-8'))
        require(iq.shape == (9,512,16,2), 'Expected actual nine-frame 512-period plan')
        require(meta['active_channel_mask'] == 0x7f7f, 'Wrong channel mask')
        for ordinal in range(9):
            fp = ordinal//gains.shape[1]
            x = iq[ordinal].astype(np.int64)
            ii,qq = x[:,:,0].T, x[:,:,1].T
            rr,ri = ii@ii.T+qq@qq.T, qq@ii.T-ii@qq.T
            ar,ai = steering[fp,:,0].tolist(),steering[fp,:,1].tolist()
            w,info = solve_fixed(rr.tolist(),ri.tolist(),ar,ai,active_mask=0x7f7f)
            beam = beam_fixed(ii.tolist(),qq.tolist(),w)
            np.testing.assert_array_equal(w,weights[ordinal])
            np.testing.assert_array_equal(beam,expected[ordinal])
            require(w[7] == (0,0) and w[15] == (0,0), 'Disabled weights are nonzero')
            require(info['active_channels'] == 14, 'Wrong solver active count')
            if ordinal == 0:
                ii_dirty,qq_dirty=ii.copy(),qq.copy()
                ii_dirty[[7,15]] = [ [32767]*512, [-32768]*512 ]
                qq_dirty[[7,15]] = [ [-32768]*512, [32767]*512 ]
                rd=ii_dirty@ii_dirty.T+qq_dirty@qq_dirty.T
                id_=qq_dirty@ii_dirty.T-ii_dirty@qq_dirty.T
                wd,_=solve_fixed(rd.tolist(),id_.tolist(),ar,ai,active_mask=0x7f7f)
                require(wd == w, 'Closed-channel extrema changed weights')
                require(beam_fixed(ii_dirty.tolist(),qq_dirty.tolist(),wd) == beam,
                        'Closed-channel extrema changed outputs')
            report('integer_frame_'+str(ordinal), weights=16, complex_outputs=512)
        report('disabled_channels_extrema_invariance', excluded=[7,15])

        config=configuration(steering[0,:,0].tolist(),steering[0,:,1].tolist(),10,0,0)
        packet_iq=iq_packets(iq[0,:,:,0].reshape(-1).tolist(),iq[0,:,:,1].reshape(-1).tolist(),9,10,0,0)
        packets=result_packets([tuple(map(int,p)) for p in expected[0]],9,10,0,0)
        for packet in [config]+packet_iq+packets:
            require(decode(packet.encode()) == packet, 'Packet roundtrip failed')
        rebuilt=np.frombuffer(b''.join(p.payload for p in packet_iq),dtype='>i2').reshape(512,16,2)
        np.testing.assert_array_equal(rebuilt,iq[0])
        require([x for p in packets for x in beam_values(p)] == [tuple(map(int,x)) for x in expected[0]],
                'Result 48-bit reconstruction failed')

        boundaries=[(-(1<<47)+k,(1<<47)-1-k) for k in range(512)]
        boundary_packets=result_packets(boundaries,9,10,0,0)
        require([x for p in boundary_packets for x in beam_values(decode(p.encode()))] == boundaries,
                'Signed48 boundaries failed')
        extrema=iq_packets([-32768,32767]*4096,[32767,-32768]*4096,9,10,0,0)
        require(np.frombuffer(b''.join(p.payload for p in extrema),dtype='>i2').reshape(512,16,2)[511,15].tolist()
                == [32767,-32768], 'Signed16 boundaries failed')
        report('BFM1_v2_roundtrip_and_boundaries', IQ_packets=32, result_packets=16, complex_outputs=512)

        rejected=0
        invalid=[config.encode()[:-1],b'',replace(config,count=2)]
        wrong=bytearray(config.encode());wrong[4]=1;invalid.append(bytes(wrong))
        for value in invalid:
            try:
                decode(value.encode() if isinstance(value,Packet512) else value)
            except ValueError:
                rejected+=1
            else:
                raise AssertionError('Malformed packet was accepted')

        responses=[Packet512(ACK,0,10,0,0)]
        responses += [Packet512(IQ_ACK,9,10,0,0,k,32) for k in range(32)]
        responses += packets

        class OfflineWire:
            def __init__(self,values):
                self.values=list(values)
                self.sent=[]
            def send(self,data):
                self.sent.append(data)
                return len(data)
            def recv(self,size):
                return self.values.pop(0).encode()

        fake=OfflineWire(responses)
        require(exchange(fake,config,packet_iq) == packets, 'Offline ACK/RESULT exchange failed')
        require(len(fake.sent)==33 and not fake.values, 'Incomplete offline exchange')
        for kind in ('duplicate','stale','error'):
            values=list(responses)
            if kind=='duplicate':values[-1]=values[-2]
            elif kind=='stale':values[-1]=replace(values[-1],config_id=11)
            else:values[-1]=Packet512(0xff,9,10,0,0,status=7)
            try:
                exchange(OfflineWire(values),config,packet_iq)
            except (ValueError,RuntimeError):
                rejected+=1
            else:
                raise AssertionError('Injected '+kind+' response was accepted')
        report('malformed_and_stale_packet_rejection', rejected_cases=rejected,
               wire='in-memory only; no sockets created')

        for folder in ('hardware_20261028','hardware_20261029'):
            hw=json.loads((ROOT/'metrics/evidence/beamforming'/folder/'scan_summary.json').read_text(encoding='utf-8'))
            require(hw['status']=='COMPLETE_HARDWARE' and hw['verified_frames']==hw['planned_frames']==4838,
                    'Historical hardware summary mismatch')
        report('historical_hardware_summary_consistency', batches=2, frames_per_batch=4838,
               new_hardware_test=False)
        result['status']='PASS_OFFLINE_PACKAGE'
    except Exception as exc:
        result['status']='FAIL'
        result['error']=str(exc)
        log.append(traceback.format_exc())
        print(log[-1],file=sys.stderr)
    finally:
        stem=logdir/('package_verification_'+tag)
        stem.with_suffix('.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        stem.with_suffix('.log').write_text('\n'.join(log)+'\n',encoding='utf-8')
        print('STATUS '+result['status'],flush=True)
        print('RESULT '+str(stem.with_suffix('.json')),flush=True)
    return 0 if result['status']=='PASS_OFFLINE_PACKAGE' else 1


if __name__=='__main__':
    raise SystemExit(main())
