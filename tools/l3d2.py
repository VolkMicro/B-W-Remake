import struct,sys
d=open(sys.argv[1],'rb').read()
P=5430260; n=626; offs=struct.unpack_from('<%dI'%n,d,P+8)
def mesh(i):
  q=P+offs[i]; h=struct.unpack_from('<19I',d,q+4)
  flags,size,nsub,subOO=h[0:4]
  print('mesh',i,'flags',hex(flags),'size',size,'nsub',nsub,'hdr',h[4:])
  subo=struct.unpack_from('<%dI'%nsub,d,q+subOO)
  for s in subo:
    sf,nprim,primo,nb,bo=struct.unpack_from('<5I',d,q+s)
    print(' sub',hex(sf),nprim,primo,nb,bo)
    po=struct.unpack_from('<%dI'%nprim,d,q+primo)
    for pp in po:
      ph=struct.unpack_from('<12I',d,q+pp); print('  prim',ph)
      sk,a,u,c,nv,vo,nt,to,ng,go,nvb,vbo=ph
      vs=[struct.unpack_from('<8f',d,q+vo+k*32) for k in range(nv)]
      xs=[v[0] for v in vs];ys=[v[1] for v in vs];zs=[v[2] for v in vs]
      print('   bbox',min(xs),max(xs),min(ys),max(ys),min(zs),max(zs),'uv',vs[0][3:5],'n',vs[0][5:8])
      tr=struct.unpack_from('<%dH'%(nt*3),d,q+to); print('   tri max',max(tr),nv)
      if ng: print('   groups',struct.unpack_from('<%dI'%ng,d,q+go) if ng<20 else ng)
    if nb and nb<50:
      for b in range(min(nb,3)): print('   bone',struct.unpack_from('<3I12f',d,q+bo+b*60))
for i in map(int,sys.argv[2:]): mesh(i)
