import struct,sys
d=open(sys.argv[1],'rb').read()
bc=struct.unpack_from('<I',d,0)[0]
lut=d[4:4+1024]
mc,cc,bs,ms,cs,lrc=struct.unpack_from('<6I',d,4+1024)
print('blocks',bc,'mats',mc,'countries',cc,'bsize',hex(bs),'msize',hex(ms),'csize',hex(cs),'lowres',lrc,'len',len(d))
tail=65536*2
end=len(d)-tail
mat0=end-mc*ms; c0=mat0-cc*cs; b0=c0-(bc-1)*bs
print('blocks start',b0,'header end',4+1024+24)
nz=[(i,x) for i,x in enumerate(lut) if x]; print('lut nonzero',len(nz),nz[:5],max(x for i,x in nz))
# lowres
p=4+1024+24
for i in range(lrc):
  u=struct.unpack_from('<4I',d,p); sz=struct.unpack_from('<I',d,p+16)[0]; print('lr',u,sz); p+=16+sz
print('after lowres',p)
