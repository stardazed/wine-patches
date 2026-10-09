# Wine patches for Photoshop 27 (against vanilla wine-11.19)

## Just want to run Photoshop?

Download a ready-made build from the [Releases page](https://github.com/stardazed/wine-patches/releases). No patching or compiling needed.

- `...-amd64-wow64.tar.xz`: use as a custom Wine runner in Lutris, Bottles or Heroic.
- `...-compattool.tar.xz`: for Steam. Extract into `~/.steam/root/compatibilitytools.d/`, restart Steam, then pick it under Properties > Compatibility.

Then install these in your prefix:
```sh
$ winetricks vkd3d dxvk gdiplus corefonts d3dcompiler_43 d3dcompiler_47 msxml3 msxml6
```


| Build | Status | Notes |
|---|---|---|
| Adobe Photoshop 2026 27.10 (20260824.r.26 9d9635d) | ✅ | Drag & Drop doesn't work. |
| Adobe Photoshop 2026 27.11 | ⚠️ | not tested |
<img width="1920" height="1080" alt="10-07_10-42-48" src="https://github.com/user-attachments/assets/2ad8250b-8179-4eee-ac35-4027a11ab8f3" />


## For developers

Apply in this order from the top of the source tree: `for f in patches/11.19/*.patch; do patch -p1 < $f; done`
(the file names sort correctly: the d2d1/dwrite ones are independent of the dxcore series).

| patch | what | status |
|---|---|---|
| d2d1-0001 | `DrawGeometryRealization` forwards to `FillGeometry`/`DrawGeometry` instead of doing nothing on non-command-list targets | fixes the missing UI painting. |
| dwrite-0001 | implements `HitTestPoint` (was a bare E_NOTIMPL) by walking clusters | works for short UI strings; O(n^2) on long text, inline objects / vertical flow not handled |
| 0001-dxcore | `IsPropertySupported` reports what `GetProperty`/`GetPropertySize` actually support (was: always FALSE, a stub that gave a false answer) | ... |
| 0002-dxcore | `IsDetachable` (property 13) as a semi-stub: FIXME + FALSE, same convention as the existing `IsHardware`/`DedicatedSystemMemory` | removes the need for patch_libxpuinfo.py |
| 0003-dxcore-tests | tests for the above; `todo_wine` documents that `IsIntegrated` is still missing | ... |

`IsIntegrated` (12) is intentionally NOT implemented because wined3d does not expose the adapter type (Vulkan deviceType is not captured), so any value would be a guess. Adobe's LibXPUInfo tolerates its absence.

## Build from source

Package names are for Ubuntu/Debian. Builds a full 64-bit Wine with WoW64 (no 32-bit libs needed).

Install dependencies:
```sh
sudo apt install build-essential autoconf automake libtool bison flex gperf perl pkg-config \
  gcc-mingw-w64-x86-64 gcc-mingw-w64-i686 ccache wget xz-utils \
  libx11-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev libxfixes-dev \
  libxrender-dev libxcomposite-dev libxinerama-dev libxxf86vm-dev libxkbcommon-dev \
  libxkbcommon-x11-dev libwayland-dev wayland-protocols libegl-dev libgl-dev libvulkan-dev \
  libfreetype-dev libfontconfig-dev libpulse-dev libasound2-dev libudev-dev \
  libusb-1.0-0-dev libsdl2-dev libgnutls28-dev libunwind-dev libdbus-1-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libcups2-dev libsane-dev \
  libv4l-dev libpcap-dev libkrb5-dev libcap2-dev libgphoto2-dev libopenal-dev \
  libsystemd-dev libxml2-dev libxslt1-dev libpcsclite-dev
```

Get the source and apply the patches (run from this repo's root):
```sh
wget https://dl.winehq.org/wine/source/11.x/wine-11.19.tar.xz
mkdir wine && tar xf wine-11.19.tar.xz -C wine --strip-components=1
for f in patches/11.19/*.patch; do patch -d wine -Np1 < $f; done
(cd wine && tools/make_requests && tools/make_specfiles && autoreconf -f)
```

Build and install to your home directory:
```sh
mkdir build && cd build
../wine/configure --enable-archs=i386,x86_64 --prefix=$HOME/wine-11.19-patched \
  --without-oss --disable-winemenubuilder --disable-tests CFLAGS="-O2" CROSSCFLAGS="-O2"
make -j"$(nproc)"
make install
```

Check it:
```sh
$HOME/wine-11.19-patched/bin/wine --version
```

Install the winetricks verbs into a new prefix using your build:
```sh
export WINE=$HOME/wine-11.19-patched/bin/wine WINEPREFIX=$HOME/.wine-photoshop
winetricks vkd3d dxvk gdiplus corefonts d3dcompiler_43 d3dcompiler_47 msxml3 msxml6
```

To use it from Lutris, Bottles or Heroic, add `~/wine-11.19-patched` as a custom Wine runner.