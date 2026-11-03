"""Transfer the real C3 input/output using UDP, then finish YOLO on the host."""
import argparse
import json
import secrets
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
CASE=ROOT/'fpga/build/recognition/board_case'
MAGIC=0x594f4c4f
class Board:
    def __init__(self):
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.sock.bind(('192.0.2.2',1234))
        self.sock.connect(('192.0.2.1',1234))
        self.seq=secrets.randbits(30)
        self.retries=0
        self.packets=0

    def transaction(self,op,addr,count,words=()):
        self.seq=(self.seq+1)&0xffffffff
        packet=struct.pack('!5I',MAGIC,self.seq,op,addr,count)
        if op==1:packet+=struct.pack(f'!{count}I',*words)
        for attempt in range(4):
            self.sock.send(packet)
            deadline=time.perf_counter()+.75
            while time.perf_counter()<deadline:
                self.sock.settimeout(max(.001,deadline-time.perf_counter()))
                try:reply=self.sock.recv(2048)
                except socket.timeout:break
                if len(reply)<16 or len(reply)%4:continue
                magic,seq,status,n=struct.unpack('!4I',reply[:16])
                if magic!=MAGIC or seq!=self.seq:continue
                if status:raise RuntimeError(f'FPGA rejected command: status={status}, address={addr:x}')
                expected=count if op==2 else 0
                if n!=expected or len(reply)!=16+n*4:raise RuntimeError('Invalid FPGA reply length')
                self.packets+=1
                return list(struct.unpack(f'!{n}I',reply[16:])) if n else []
            self.retries+=1
        raise TimeoutError(f'FPGA UDP timeout opcode={op}, address=0x{addr:x}, seq={self.seq}')

    def rd(self,addr,count=1):return self.transaction(2,addr,count)
    def wr(self,addr,words):return self.transaction(1,addr,len(words),words)
    def compute(self,nonce):
        self.wr(4,[nonce]);self.wr(0,[1])
        deadline=time.perf_counter()+10
        while self.rd(0)[0]!=1:
            if time.perf_counter()>deadline:raise TimeoutError('FPGA convolution timed out')
            time.sleep(.005)
        if self.rd(4)[0]!=nonce:raise RuntimeError('Returned nonce does not match this run')
    def download(self,name,batch_words=360):
        with (CASE/name).open('w',encoding='ascii') as f:
            for pos in range(0,32768,batch_words):
                values=self.rd(0x400000+pos*4,min(batch_words,32768-pos))
                f.write(''.join(f'{v:08x}' for v in reversed(values))+'\n')

def save_words(name,values):
    (CASE/name).write_text(''.join(f'{v:08x}' for v in reversed(values))+'\n',encoding='ascii')
