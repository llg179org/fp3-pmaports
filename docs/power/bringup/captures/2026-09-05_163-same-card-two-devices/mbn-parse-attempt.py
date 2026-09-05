import re, sys, struct
# Heuristic reader: every EFS item embeds its path as a NUL-terminated string,
# immediately followed by uint16 data_len and that many value bytes.
# Validated below against sms_domain_pref, whose length must be 2.
PATH = re.compile(rb'/(?:nv|ims|sd)/[!-~]{4,120}\x00')
def items(fn):
    b = open(fn,'rb').read()
    out = {}
    for m in PATH.finditer(b):
        path = m.group(0)[:-1].decode('ascii','replace')
        p = m.end()
        if p+2 > len(b): continue
        n = struct.unpack_from('<H', b, p)[0]
        if n == 0 or n > 4096 or p+2+n > len(b): continue
        out.setdefault(path, []).append(b[p+2:p+2+n])
    return out

files = {'ROW':'row.mbn', 'VF-HU':'vfhu.mbn', 'VFglob':'vfglobal.mbn'}
data = {k: items(v) for k,v in files.items()}

def show(path, note=''):
    print(f"\n{path}  {note}")
    for k in files:
        vs = data[k].get(path)
        if not vs: print(f"   {k:8s} absent"); continue
        for v in vs:
            hexs = v.hex(' ')
            dec = ''
            if len(v) in (1,2,4):
                dec = f"  = {int.from_bytes(v,'little')}"
            print(f"   {k:8s} len={len(v):<4d} {hexs[:60]}{dec}")

print("=== GATE: sms_domain_pref must be a short item (known shape) ===")
show('/nv/item_files/modem/mmode/sms_domain_pref')
print("\n=== THE DISCRIMINATOR ===")
show('/nv/item_files/modem/mmode/voice_domain_pref',
     '0=CS only, 1=PS only, 2=CS preferred, 3=PS preferred')

print("\n=== NEGATIVE CONTROL: does this parser EVER see a difference? ===")
allp = set()
for k in data: allp |= set(data[k])
diff = same = 0
examples = []
for p in sorted(allp):
    vals = {k: (data[k].get(p) or [None])[0] for k in files}
    if any(v is None for v in vals.values()):
        continue
    if len(set(vals.values())) > 1:
        diff += 1
        if len(examples) < 8:
            examples.append((p, {k: (v.hex(' ')[:34] if v else '-') for k,v in vals.items()}))
    else:
        same += 1
print(f"items present in all three: {same+diff}   identical: {same}   DIFFERING: {diff}")
for p, v in examples:
    print(f"\n  {p}")
    for k in files: print(f"     {k:8s} {v[k]}")

print("\n=== the IMS blobs, explicitly ===")
for p in ['/nv/item_files/ims/qp_ims_service_enablement_config',
          '/nv/item_files/ims/IMSVoiceDynamicConfig',
          '/nv/item_files/ims/qp_ims_common_config',
          '/nv/item_files/ims/RegistrationConfiguration',
          '/nv/item_files/ims/IMS_enable']:
    show(p)

print("\n=== coverage: items found per file, and which are unique ===")
for k in files:
    print(f"  {k:8s} {len(data[k])} path-items recovered")
only_hu = set(data['VF-HU']) - set(data['ROW'])
only_row = set(data['ROW']) - set(data['VF-HU'])
print(f"\n  only in VF-HU ({len(only_hu)}): " + ', '.join(sorted(only_hu))[:400])
print(f"\n  only in ROW  ({len(only_row)}): " + ', '.join(sorted(only_row))[:400])
