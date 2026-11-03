"""Build one complete joint512 transaction from a frozen prepared plan."""
from udp512 import configuration,iq_packets,result_packets


def requests(plan,ordinal,nonce):
    fp,lp,_=plan.coordinate(ordinal)
    cid=(nonce+2*ordinal)&0xffffffff;fid=(nonce+2*ordinal+1)&0xffffffff
    frequency=plan.meta['source_frequency_index'][fp];lag=plan.meta['relative_lag_samples'][lp]
    cfg=configuration(plan.steering[fp,:,0].tolist(),plan.steering[fp,:,1].tolist(),cid,frequency,lag)
    x=plan.iq[ordinal]
    iq=iq_packets(x[:,:,0].reshape(-1).tolist(),x[:,:,1].reshape(-1).tolist(),fid,cid,frequency,lag)
    result=result_packets(plan.expected[ordinal].tolist(),fid,cid,frequency,lag)
    return cfg,iq,result
