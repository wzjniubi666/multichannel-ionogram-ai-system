"""BFM1/version2 codec and acknowledged 512-period transaction. No v1 fallback."""
from dataclasses import dataclass
from udp_replay import MAGIC,HEADER,CONFIG,IQ,ACK,RESULT,ERROR,ERRORS,signed_bytes

IQ_ACK=0x83


@dataclass(frozen=True)
class Packet512:
    kind:int
    frame_id:int
    config_id:int
    frequency_index:int
    gate_index:int
    index:int=0
    count:int=1
    status:int=0
    payload:bytes=b''

    def encode(self):
        data=HEADER.pack(MAGIC,2,self.kind,self.status,self.frame_id,self.config_id,
            self.frequency_index,self.gate_index,self.index,self.count,512,16,len(self.payload),0)+self.payload
        decode(data)
        return data


def decode(data):
    if len(data)<32 or len(data)>1056 or len(data)%4:raise ValueError('invalid v2 datagram size')
    magic,version,kind,status,fid,cid,freq,lag,index,count,records,channels,size,reserved=HEADER.unpack_from(data)
    if (magic,version,records,channels,reserved)!=(MAGIC,2,512,16,0):raise ValueError('invalid512 protocol header')
    if size!=len(data)-32:raise ValueError('512 payload length mismatch')
    if kind==ERROR:
        if status not in ERRORS or size or count!=1:raise ValueError('invalid512 error')
    else:
        expected={CONFIG:(96,1),IQ:(1024,32),ACK:(0,1),IQ_ACK:(0,32),RESULT:(384,16)}
        if kind not in expected or status or (size,count)!=expected[kind] or index>=count:
            raise ValueError('invalid512 type, size or packet index/count')
        if kind in (CONFIG,ACK) and fid!=0:raise ValueError('configuration frame_id must be0')
    return Packet512(kind,fid,cid,freq,lag,index,count,status,data[32:])


def configuration(re,im,cid,freq,lag):
    if len(re)!=16 or len(im)!=16:raise ValueError('16 steering coefficients required')
    return Packet512(CONFIG,0,cid,freq,lag,payload=b''.join(signed_bytes(r,24)+signed_bytes(i,24) for r,i in zip(re,im)))


def iq_packets(ii,qq,fid,cid,freq,lag):
    if len(ii)!=8192 or len(qq)!=8192:raise ValueError('512periods x16channels required')
    raw=b''.join(signed_bytes(r,16)+signed_bytes(i,16) for r,i in zip(ii,qq))
    return [Packet512(IQ,fid,cid,freq,lag,index,32,payload=raw[index*1024:(index+1)*1024]) for index in range(32)]


def result_packets(values,fid,cid,freq,lag):
    if len(values)!=512:raise ValueError('512 output samples required')
    data=b''.join(signed_bytes(r,48)+signed_bytes(i,48) for r,i in values)
    return [Packet512(RESULT,fid,cid,freq,lag,index,16,payload=data[index*384:(index+1)*384]) for index in range(16)]


def beam_values(packet):
    if packet.kind!=RESULT:raise ValueError('not a512 RESULT')
    return [(int.from_bytes(packet.payload[n:n+6],'big',signed=True),
             int.from_bytes(packet.payload[n+6:n+12],'big',signed=True)) for n in range(0,len(packet.payload),12)]


def exchange(sock,config,packets):
    if config.kind!=CONFIG or len(packets)!=32:raise ValueError('CONFIG +32IQ required')
    fid=packets[0].frame_id
    for index,packet in enumerate(packets):
        if (packet.kind,packet.frame_id,packet.config_id,packet.frequency_index,packet.gate_index,packet.index,packet.count)!=(
            IQ,fid,config.config_id,config.frequency_index,config.gate_index,index,32):raise ValueError('IQ512 sequence/identity mismatch')
    def receive(kind,frame,index,count):
        packet=decode(sock.recv(2048))
        if (packet.frame_id,packet.config_id,packet.frequency_index,packet.gate_index)!=(frame,config.config_id,config.frequency_index,config.gate_index):
            raise ValueError('stale/foreign512 response metadata')
        if packet.kind==ERROR:raise RuntimeError('FPGA512 '+ERRORS[packet.status])
        if (packet.kind,packet.index,packet.count)!=(kind,index,count):raise ValueError('512 response sequence mismatch')
        return packet
    sock.send(config.encode());receive(ACK,0,0,1)
    for index,packet in enumerate(packets):
        sock.send(packet.encode());receive(IQ_ACK,fid,index,32)
    return [receive(RESULT,fid,index,16) for index in range(16)]
