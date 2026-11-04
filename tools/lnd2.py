import struct,sys
d=open(sys.argv[1],'rb').read()
for b0 in (460812,462432):
  for k in range(3):
    m=b0+k*2520+2312
    print(b0,k,struct.unpack_from('<12I',d,m))
  # altitudes of first cells
  print([d[b0+i*8+4] for i in range(20)], [d[b0+i*8:b0+i*8+8].hex() for i in range(3)])
