# Wine patches for Photoshop 27 (against vanilla wine-11.19)

| Build | Status | Notes |
|---|---|---|
| Adobe Photoshop 2026 27.10 (20260824.r.26 9d9635d) | ✅ | launches, AI mode doesn't work. |
| Adobe Photoshop 2026 27.11 | ⚠️ | not tested |

Apply in this order from the top of the source tree: `for f in wine-patches/*.patch; do patch -p1 < $f; done`
(the file names sort correctly: the d2d1/dwrite ones are independent of the dxcore series).

| patch | what | status |
|---|---|---|
| d2d1-0001 | `DrawGeometryRealization` forwards to `FillGeometry`/`DrawGeometry` instead of doing nothing on non-command-list targets | fixes the missing UI painting. |
| dwrite-0001 | implements `HitTestPoint` (was a bare E_NOTIMPL) by walking clusters | works for short UI strings; O(n^2) on long text, inline objects / vertical flow not handled |
| 0001-dxcore | `IsPropertySupported` reports what `GetProperty`/`GetPropertySize` actually support (was: always FALSE, a stub that gave a false answer) | ... |
| 0002-dxcore | `IsDetachable` (property 13) as a semi-stub: FIXME + FALSE, same convention as the existing `IsHardware`/`DedicatedSystemMemory` | removes the need for patch_libxpuinfo.py |
| 0003-dxcore-tests | tests for the above; `todo_wine` documents that `IsIntegrated` is still missing | ... |

`IsIntegrated` (12) is intentionally NOT implemented because wined3d does not expose the adapter type (Vulkan deviceType is not captured), so any value would be a guess. Adobe's LibXPUInfo tolerates its absence.

After patching and building, install these verbs:
```sh
$ winetricks vkd3d dxvk gdiplus corefonts d3dcompiler_43 d3dcompiler_47 msxml3 msxml6
```

## Build only the changed DLLs

```
tar xf wine-11_19_tar.xz && cd wine-11.19 && for f in ../wine-patches/*.patch; do patch -p1 < $f; done
mkdir ../build && cd ../build && ../wine-11.19/configure --enable-win64 --disable-tests   # drop --disable-tests to build the tests
make -j"$(nproc)" dlls/d2d1/all dlls/dwrite/all dlls/dxcore/all     # if this target form is rejected, run a plain `make -j`
# back up, then copy the PE builtins into your 11.18 install:
cp dlls/d2d1/x86_64-windows/d2d1.dll dlls/dwrite/x86_64-windows/dwrite.dll dlls/dxcore/x86_64-windows/dxcore.dll  <wine>/lib/wine/x86_64-windows/
```
