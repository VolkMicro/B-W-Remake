import struct,sys
d=open(sys.argv[1],'rb').read()
p=5430260
print(d[p:p+4], struct.unpack_from('<I',d,p+4))
n=struct.unpack_from('<I',d,p+4)[0]
offs=struct.unpack_from('<%dI'%n,d,p+8)
info=d[5426124:5426124+4100]
print(offs[:6])
for i in range(3):
  q=p+offs[i]; print(i, d[q:q+4], struct.unpack_from('<24I',d,q+4))
# names in AllMeshes.h
