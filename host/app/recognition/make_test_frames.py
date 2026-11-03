"""Exercise maximum frames through the actual gigabit RGMII/UDP/AXI path."""
from pathlib import Path
import shutil
import struct
import zlib
root=Path(__file__).resolve().parents[3]
case=root/'fpga/build/recognition/board_case'
host=bytes.fromhex('020000000002');board=bytes.fromhex('020000000001')
hip=bytes([192,0,2,2]);bip=bytes([192,0,2,1])
def udp(src,dst,sip,dip,payload,ident):
    h=struct.pack('!BBHHHBBH4s4s',0x45,0,len(payload)+28,ident,0x4000,64,17,0,sip,dip)
    c=sum(struct.unpack('!10H',h))
    while c>>16:c=(c&65535)+(c>>16)
    h=h[:10]+struct.pack('!H',~c&65535)+h[12:]
    eth=(dst+src+b'\x08\x00'+h+struct.pack('!HHHH',1234,1234,len(payload)+8,0)+payload).ljust(60,b'\x00')
    return eth+struct.pack('<I',zlib.crc32(eth))
def mem(name,data):
    (case/name).write_text(''.join(f'{v:02x}\n' for v in data))
requests=[([0x594f4c4f,1,2,12,1],[0x594f4c4f,1,0,1,0x594f4c47]),
          ([0x594f4c4f,2,1,0x100ffc,360]+[0x7f123400+i for i in range(360)],[0x594f4c4f,2,0,0]),
          ([0x594f4c4f,3,2,0x400ffc,360],[0x594f4c4f,3,0,360]+[0xaabbcc00+i for i in range(360)])]
sizes=[]
for i,(req,rep) in enumerate(requests,1):
    a=udp(host,board,hip,bip,struct.pack(f'!{len(req)}I',*req),10)
    b=b'\x55'*7+b'\xd5'+udp(board,b'\xff'*6,bip,hip,struct.pack(f'!{len(rep)}I',*rep),i)
    mem(f'cmd{i}.mem',a);mem(f'res{i}.mem',b);sizes.append((len(a),len(b)))
