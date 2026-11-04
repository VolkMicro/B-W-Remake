import struct,sys
for fn in sys.argv[1:]:
  d=open(fn,'rb').read(); p=8; print(fn,len(d))
  while p+36<=len(d):
    name=d[p:p+32].split(b'\0')[0].decode('latin1'); sz=struct.unpack_from('<I',d,p+32)[0]
    print('  ',name,p+36,sz, d[p+36:p+36+48].hex()); p+=36+sz
