#!/usr/bin/env python3
"""patch_libxpuinfo.py - make Adobe's LibXPUInfo.dll survive Wine's missing DXCore property IsDetachable (13).

Problem (verified from your logs + disassembly): in Device::initDXCoreDevice's helper, after
    call IDXCoreAdapter::GetProperty(IsDetachable=13, ...)
the code does  `test eax,eax ; js THROW`  and THROW builds+throws winrt::hresult_error. Wine's dxcore returns
DXGI_ERROR_INVALID_CALL for property 13, so Photoshop's GPU/XPU enumeration throws.

Patch: the 41-byte THROW block is replaced by
    mov BYTE PTR [rsp+0x88], 0      ; IsDetachable = FALSE
    jmp <instruction after the js>  ; carry on exactly as if the call had succeeded
Nothing else is touched (13 bytes written, the rest of the block becomes int3). Position independent, stays inside
the function's .pdata range, no stack/unwind change.

  patch_libxpuinfo.py LibXPUInfo.dll            # check only
  patch_libxpuinfo.py LibXPUInfo.dll --apply    # backs up to LibXPUInfo.dll.orig, then patches
  patch_libxpuinfo.py LibXPUInfo.dll --revert   # restores from .orig

Modifies a binary of your own licensed Adobe install for local Wine compatibility; the Authenticode signature
becomes invalid (Wine does not check it). Do not redistribute the patched file. Keep the .orig.
"""
import sys, shutil, hashlib, struct, os

PATTERN = bytes.fromhex('85c0 78 72 834b1040 c1ef1f'.replace(' ', ''))      # test eax,eax; js +0x72; or [rbx+0x10],0x40; shr edi,0x1f
THROW_HEAD = bytes.fromhex('8bd0 488d4c2430 e8'.replace(' ', ''))            # mov edx,eax; lea rcx,[rsp+0x30]; call rel32
MOV_BYTE_0 = bytes.fromhex('c6842488000000' + '00')                           # mov BYTE PTR [rsp+0x88],0   (8 bytes)


def md5(b): return hashlib.md5(b).hexdigest()


def find(data):
    hits = []; i = data.find(PATTERN)
    while i != -1:
        hits.append(i); i = data.find(PATTERN, i + 1)
    return hits


def plan(data):
    hits = find(data)
    if len(hits) != 1: return None, 'expected exactly 1 match of the js pattern, found %d (different build?)' % len(hits)
    p = hits[0]; js_at = p + 2; after_js = js_at + 2; throw_at = after_js + data[js_at + 1]
    if data[throw_at:throw_at + len(THROW_HEAD)] == THROW_HEAD:
        # find end of the throw block: it ends with int3 (0xCC) after the last call
        end = throw_at
        while end < len(data) and data[end] != 0xCC: end += 1
        return dict(throw_at=throw_at, end=end, after_js=after_js, patched=False), None
    cave = MOV_BYTE_0 + b'\xe9'
    if data[throw_at:throw_at + len(cave)] == cave:
        return dict(throw_at=throw_at, after_js=after_js, patched=True), None
    return None, 'bytes at the js target are neither the original throw block nor our patch'


def main():
    if len(sys.argv) < 2: sys.exit(__doc__)
    path = sys.argv[1]; mode = sys.argv[2] if len(sys.argv) > 2 else '--check'
    orig = path + '.orig'
    if mode == '--revert':
        if not os.path.exists(orig): sys.exit('no %s to restore' % orig)
        shutil.copyfile(orig, path); print('restored', path, md5(open(path, 'rb').read())); return
    data = bytearray(open(path, 'rb').read())
    pl, err = plan(bytes(data))
    if err: sys.exit('REFUSING: ' + err)
    print('file md5 %s  size %d' % (md5(bytes(data)), len(data)))
    print('js target (throw block) at file offset 0x%x, block length %s' % (pl['throw_at'], ('%d bytes' % (pl['end'] - pl['throw_at'])) if not pl['patched'] else 'already patched'))
    if pl['patched']: print('STATUS: already patched'); return
    if mode != '--apply': print('STATUS: original, patchable (use --apply)'); return
    n = pl['end'] - pl['throw_at']
    if n < 13: sys.exit('REFUSING: throw block too small (%d)' % n)
    if not os.path.exists(orig): shutil.copyfile(path, orig); print('backup ->', orig)
    rel = pl['after_js'] - (pl['throw_at'] + 8 + 5)                           # jmp rel32 back to the instruction after the js
    new = MOV_BYTE_0 + b'\xe9' + struct.pack('<i', rel)
    data[pl['throw_at']:pl['throw_at'] + len(new)] = new
    for k in range(pl['throw_at'] + len(new), pl['end']): data[k] = 0xCC
    open(path, 'wb').write(bytes(data))
    print('PATCHED. new md5 %s' % md5(bytes(data)))


if __name__ == '__main__':
    main()
