"""Calibrate and generate independent integer references for 15 convolutions."""
import hashlib
import json
import os
import sys
from pathlib import Path
import numpy as np
import torch
ROOT=Path(__file__).resolve().parents[3]
from project_paths import resolve_asset
OUT=ROOT/'fpga/build/recognition/board_case'
os.environ['YOLO_CONFIG_DIR']=str(ROOT/'host/deploy/recognition/ultralytics_config')
sys.path.insert(0,str(ROOT/'host/app/recognition/vendor'))
from ultralytics import YOLO
import cv2
def preprocess(path,height,width):
    image=cv2.imdecode(np.fromfile(str(path),dtype=np.uint8),cv2.IMREAD_COLOR)
    if image is None:raise ValueError(path)
    h,w=image.shape[:2];ratio=min(height/h,width/w)
    nw,nh=round(w*ratio),round(h*ratio)
    image=cv2.resize(image,(nw,nh));dw,dh=(width-nw)/2,(height-nh)/2
    image=cv2.copyMakeBorder(image,round(dh-.1),round(dh+.1),round(dw-.1),round(dw+.1),cv2.BORDER_CONSTANT,value=(114,114,114))
    return np.ascontiguousarray(image[:,:,::-1].transpose(2,0,1)[None],dtype=np.float32)/255.
selection=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
selected=[resolve_asset(p) for p in selection['test_images']]
calibration=[resolve_asset(p) for p in selection['calibration_images']]

torch.set_num_threads(4)
def mem(name,values,bits):
    (OUT/name).write_text(''.join(f'{int(v)&((1<<bits)-1):0{bits//4}x}\n' for v in np.asarray(values).ravel()),encoding='ascii')
def const(name,values,bits):
    v=np.asarray(values).ravel()
    return f"localparam [{v.size*bits-1}:0] {name} = {v.size*bits}'h"+''.join(f'{int(x)&((1<<bits)-1):0{bits//4}x}' for x in v[::-1])+';\n'
model=YOLO(str(ROOT/'host/model/recognition/best.pt')).model.eval().fuse(verbose=False)
a,b=model.model[2],model.model[4]
assert len(a.m)==1 and len(b.m)==2
assert all(block.add for block in [*a.m,*b.m])
layers=[model.model[0],model.model[1],a.cv1,a.m[0].cv1,a.m[0].cv2,a.cv2,a.cv3,
        model.model[3],b.cv1,b.m[0].cv1,b.m[0].cv2,b.m[1].cv1,b.m[1].cv2,b.cv2,b.cv3]
names=['front.conv1','front.conv2','c3a.cv1','c3a.b0.cv1','c3a.b0.cv2','c3a.cv2','c3a.cv3',
       'downsample.conv','c3b.cv1','c3b.b0.cv1','c3b.b0.cv2','c3b.b1.cv1','c3b.b1.cv2','c3b.cv2','c3b.cv3']
inputs=[None,0,1,2,3,1,(4,5),6,7,8,9,10,11,7,(12,13)]
residuals={4:2,10:8,12:10}
strides=[2,2,1,1,1,1,1,2,1,1,1,1,1,1,1]
pads=[2,1,0,0,1,0,0,1,0,0,1,0,1,0,0]
def input_for(i,outputs,first):
    source=inputs[i]
    if source is None:return first
    if isinstance(source,tuple):
        return torch.cat([outputs[s] for s in source],1) if isinstance(outputs[0],torch.Tensor) else np.concatenate([outputs[s] for s in source],1)
    return outputs[source]
x=preprocess(selected[0],256,256)
xq=np.rint(x*255).astype(np.uint8)
float_out=[];float_z=[]
with torch.no_grad():
    for i,layer in enumerate(layers):
        inp=input_for(i,float_out,torch.from_numpy(x))
        z=layer.conv(inp);out=torch.nn.functional.silu(z)
        if i in residuals:out=out+float_out[residuals[i]]
        float_z.append(z.numpy().copy());float_out.append(out)
maxout=np.zeros(15);maxz=np.zeros(15)
with torch.no_grad():
    for path in calibration:
        values=[]
        for i,layer in enumerate(layers):
            inp=input_for(i,values,torch.from_numpy(preprocess(path,256,256)))
            z=layer.conv(inp);out=torch.nn.functional.silu(z)
            if i in residuals:out=out+values[residuals[i]]
            maxout[i]=max(maxout[i],float(out.abs().max()))
            maxz[i]=max(maxz[i],float(z.abs().max()))
            values.append(out)
scales=maxout*1.10/32767
scales[2]=scales[4]=max(scales[2],scales[4])
scales[8]=scales[10]=scales[12]=max(scales[8],scales[10],scales[12])
bounds=2.**np.ceil(np.log2(np.maximum(1,maxz*1.25)))
factors=4096/bounds
weights=[];biases=[];multipliers=[];tables=[];bases=[];offset=0
all_b=np.zeros((16,64),np.int32);all_m=np.zeros((16,64),np.int64)
all_w=np.zeros((32,2048),np.int8);all_lut=np.zeros((16,8192),np.int16)
for i,layer in enumerate(layers):
    w=layer.conv.weight.detach().numpy().astype(np.float64)
    co,ci,kh,kw=w.shape
    src=inputs[i]
    if src is None:inscale=np.full(ci,1/255)
    elif isinstance(src,tuple):inscale=np.concatenate([np.full(float_out[s].shape[1],scales[s]) for s in src])
    else:inscale=np.full(ci,scales[src])
    effective=w*inscale[None,:,None,None]
    ws=np.maximum(np.abs(effective).max(axis=(1,2,3))/127,1e-15)
    wq=np.clip(np.rint(effective/ws[:,None,None,None]),-127,127).astype(np.int8)
    bq=np.rint(layer.conv.bias.detach().numpy()/ws).astype(np.int32)
    mult=np.rint(ws*factors[i]*(1<<24)).astype(np.int64)
    assert np.all(mult>0) and np.all(mult<(1<<23)),i
    grid=(np.arange(8192)-4096)/factors[i]
    lut=np.clip(np.rint(grid/(1+np.exp(-grid))/scales[i]),-32768,32767).astype(np.int16)
    weights.append(wq);biases.append(bq);multipliers.append(mult);tables.append(lut)
    all_b[i,:co]=bq;all_m[i,:co]=mult;all_lut[i]=lut
    bases.append(offset)
    taps=ci*kh*kw
    for oc in range(co):all_w[oc%32,offset+(oc//32)*taps:offset+(oc//32+1)*taps]=wq[oc].ravel()
    offset+=((co+31)//32)*taps
assert offset<=2048,offset
def reference(first):
    outputs=[];accs=[];ranges=[]
    for i in range(15):
        inp=input_for(i,outputs,first)
        acc=torch.nn.functional.conv2d(torch.from_numpy(inp.astype(np.float64)),torch.from_numpy(weights[i].astype(np.float64)),torch.from_numpy(biases[i].astype(np.float64)),stride=strides[i],padding=pads[i]).numpy()
        assert np.max(np.abs(acc))<(1<<31),f'Accumulator overflow stage {i}'
        acc=acc.astype(np.int32)
        index=((acc.astype(np.int64)*multipliers[i][None,:,None,None])>>24)+4096
        ranges.append([int(index.min()),int(index.max())])
        q=tables[i][np.clip(index,0,8191)]
        if i in residuals:q=np.clip(q.astype(np.int32)+outputs[residuals[i]].astype(np.int32),-32768,32767).astype(np.int16)
        outputs.append(q);accs.append(acc)
    return outputs,accs,ranges
outputs,accs,ranges=reference(xq)
challenge_x=xq.copy();challenge_x[0,:,100,100]^=255
challenge,_,_=reference(challenge_x)
assert np.any(challenge[-1]!=outputs[-1])
for i,out in enumerate(outputs):mem(f'stage{i}_golden.mem',out[0].transpose(1,2,0),16)
for c in range(32):mem(f'w{c}.mem',all_w[c],8)
for c in range(32):mem(f'bias{c}.mem',all_b.reshape(16,2,32)[:,:,c],32)
mem('silu.mem',all_lut,16);mem('coeff.mem',all_m,24)
bases=np.r_[bases,0]
(OUT/'constants.vh').write_text(const('WEIGHT_BASES',bases,12),encoding='ascii')
debug=np.stack([v[0,:4,0,0] for v in accs]);mem('debug_golden.mem',debug,32)
pixels=xq[0].transpose(1,2,0).reshape(-1,3).astype(np.uint32)
mem('input_words.txt',pixels[:,0]|pixels[:,1]<<8|pixels[:,2]<<16,32)
arrays=dict(x=x,xq=xq,golden=outputs[-1],challenge=challenge[-1],out_scale=np.asarray(scales[-1],np.float32),debug=debug,stage_scales=scales)
for i in range(15):arrays[f'stage{i}']=outputs[i]
np.savez(OUT/'case.npz',**arrays)
manifest=dict(fpga_scope='first five YOLO modules, 15 convolutions, two-tap 64 MACs',conv_names=names,conv_shapes=[list(w.shape) for w in weights],input_shape=list(x.shape),output_shape=list(outputs[-1].shape),weight_bits=8,activation_bits=16,accumulator_bits=32,activation_scales=scales.tolist(),lookup_index_ranges=ranges,weight_words_per_lane=offset,calibration_images=[p.relative_to(ROOT).as_posix() for p in calibration],test_images=[p.relative_to(ROOT).as_posix() for p in selected],model_sha256=hashlib.sha256((ROOT/'host/model/recognition/best.pt').read_bytes()).hexdigest(),class_names=model.names,architecture='64 MACs, UDP360, gigabit RGMII DDR')
(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ROOT/'metrics/evidence/recognition/fixtures').mkdir(exist_ok=True)
for index,path in enumerate(selected):
    xi=preprocess(path,256,256);xqi=np.rint(xi*255).astype(np.uint8)
    ys,zs,rs=reference(xqi)
    changed=xqi.copy();changed[0,:,100,100]^=255
    yc,_,_=reference(changed)
    assert np.any(yc[-1]!=ys[-1])
    pixels=xqi[0].transpose(1,2,0).reshape(-1,3).astype(np.uint32)
    packed=pixels[:,0]|pixels[:,1]<<8|pixels[:,2]<<16
    np.savez(ROOT/f'metrics/evidence/recognition/fixtures/image{index}.npz',x=xi,xq=xqi,words=packed,golden=ys[-1],challenge=yc[-1],debug=np.stack([z[0,:4,0,0] for z in zs]),out_scale=np.asarray(scales[-1],np.float32),image_path=path.relative_to(ROOT).as_posix())
    print('Prepared image',index,path.name,flush=True)
print(json.dumps({'calibration_images':len(calibration),'test_images':len(selected),'class_names':model.names,'weight_words_per_lane':offset},ensure_ascii=False,indent=2))
