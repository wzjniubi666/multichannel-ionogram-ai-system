clear all;
loop_num=256;
fre_start=7.1;
fre_step=0.5;
fre_end=26.1;
code_order=10;
code_width=2;
pluse_width=2;
if(code_order==5)
    load('m31a');
end
if(code_order==6)
    load('m63a');
end
if(code_order==7)
    load('m127a');
end
if(code_order==8)
    load('m255a');
end
if(code_order==9)
    load('m511a');
end
if(code_order==10)
    load('m1023a');
end
maxlengthtemp=size(code);
maxlength=maxlengthtemp(2);
SpxDB = [code,code]';
LocalCode = zeros(maxlength,maxlength);
for cl = 1:maxlength
    LocalCode(:,cl) = SpxDB(maxlength+2-cl:end+1-cl);
end

fid=fopen('example_data/example_ch_0.cos','r'); 
fseek(fid,0,'eof');
fsize = ftell(fid);
fseek(fid,-fsize,'eof');
data1=fread(fid, fsize, 'int16');
for frenum=1:(fre_end-fre_start)/fre_step+1
 for loops=1:loop_num
     Idata1=data1((frenum-1)*loop_num*maxlength*code_width*2+(loops-1)*maxlength*code_width*2+1:2:(frenum-1)*loop_num*maxlength*code_width*2+loops*maxlength*code_width*2-1);
     Qdata1=data1((frenum-1)*loop_num*maxlength*code_width*2+(loops-1)*maxlength*code_width*2+2:2:(frenum-1)*loop_num*maxlength*code_width*2+loops*maxlength*code_width*2)*j;
     IQdata1=Idata1+Qdata1;
     for num=1:code_width
         datatemp1=IQdata1(num:code_width:(maxlength-1)*code_width+num);
         corrAdata1(num:code_width:(maxlength-1)*code_width+num)=datatemp1'*LocalCode;     
     end
      AMPTEMP1(loops,:)=corrAdata1;
 end
  AMP001(frenum,:)=sum(AMPTEMP1);
  success=1;
end
z=mean(abs(AMP001(:,100:500)),2);
AMP001=abs(AMP001)-z;
amp1=20*log10(abs(AMP001));
amp1=amp1-max(max(amp1));
idx = amp1(frenum,:)<-30;   % 找出该行等于0的位置
amp1(frenum, idx) =-30;
fre=fre_start:fre_step:fre_end;
d=1:maxlength*2;
figure(1)
imagesc(fre,d*7.68,amp1');
set(gca,'YDir','normal');
set(gca,'FontSize',20,'FontWeight','bold');
xlabel('频率/ MHz','FontSize',20,'FontWeight','bold'); ylabel('群距离/ km','FontSize',20,'FontWeight','bold'); 
colorbar;
h=colorbar;
h.Label.String = '归一化能量谱/ dB ';%添加单位
set(h,'fontsize',20);%设置单位"cm"的属性，字号设置为8，选择加粗
caxis([-30 0]);
ylim([5000 9000]);
success=1;