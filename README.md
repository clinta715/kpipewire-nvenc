# KPipeWire NVENC for KRdp

[nvenc-6.8.3.patch](nvenc-6.8.3.patch) adds NVIDIA hardware H.264 encoding
to KPipeWire 6.8.3 via FFmpeg's `h264_nvenc`. It also fixes frame pacing
when capture timestamps are rounded to milliseconds, fixes lost
condition-variable wakeups in `PipeWireProduce` worker threads, drains
packets inline on video-only streams (eliminating the extra output-thread
hop and per-frame Qt event allocation), and propagates the configured
maximum frame rate from startup.

When a CUDA-capable NVIDIA EGL/GBM render node is available, DMA-BUF
frames stay on the GPU: they are imported via a bounded LRU `EGLImage`
cache (keyed by DMA-BUF device/inode), converted to BT.709 NV12 (full or
limited range, padded to even dimensions) in a single-pass OpenGL 4.3
compute shader (falling back to 2-pass GL 3.3 fragment shaders if needed),
copied VRAM-to-VRAM into pooled `AV_PIX_FMT_CUDA` surfaces via CUDA-GL
interop (`libcuda.so.1` loaded dynamically at runtime), and encoded
directly by `h264_nvenc` with zero PCIe round-trip or CPU `swscale`. If
GPU interop is unavailable (or `KPIPEWIRE_NVENC_NO_ZEROCOPY=1` is set),
it falls back to a pooled single-pass NV12 software upload path.

## Build and install

Use a Plasma 6.8.3 environment with KRdp, an NVENC-capable NVIDIA GPU and
driver, and FFmpeg with `h264_nvenc` support. Building requires a C++
toolchain, CMake, Extra CMake Modules, and KPipeWire's Qt 6, KDE Frameworks 6,
PipeWire, FFmpeg, and graphics development dependencies.

Download the [KPipeWire 6.8.3 source archive](https://download.kde.org/stable/plasma/6.8.3/kpipewire-6.8.3.tar.xz)
into the repository root. Run the build script as your regular user.

```sh
./build-install.sh --install
```

The script checks that the built library contains the NVENC encoder and
installs it under `~/.local/lib/krdp-nvenc/6.8.3/`. Running the script
without `--install` builds and stages the library under
`releases/6.8.3/stage/`.

## Enable in KRdp

Install the supplied systemd user drop-in and restart KRdp. Restarting
disconnects active RDP clients.

```sh
install -Dm644 config/50-nvenc.conf \
  ~/.config/systemd/user/app-org.kde.krdpserver.service.d/50-nvenc.conf
systemctl --user daemon-reload
systemctl --user restart app-org.kde.krdpserver.service
```

The drop-in selects the patched library and forces `h264_nvenc` when
the local library is present and readable and
`/usr/lib/libKPipeWireRecord.so.6` resolves to
`/usr/lib/libKPipeWireRecord.so.6.8.3`. If either check fails,
KRdp starts with the system library. Port the patch and update the drop-in
before using it with another KPipeWire version.

The drop-in pins KRdp at quality 70 and disables adaptive quality. This
resolved lingering blur after screen updates in testing. To change the
fixed quality, edit the `--quality 70` argument. To restore adaptive quality
and use the KDE slider, remove both `--static-quality` and `--quality 70`.
Reload systemd and restart KRdp after either change.

## Verify hardware encoding

Connect an RDP client and move a window or play a video so there are new
frames to encode. Then check the service log and NVIDIA encoder sessions.

```sh
systemctl --user show -p MainPID --value app-org.kde.krdpserver.service
journalctl --user -u app-org.kde.krdpserver.service -b | grep 'Forcing encoder'
nvidia-smi encodersessions
```

Look for `h264_nvenc` in the log and an H.264 session with the KRdp PID
in the NVIDIA output. The reported FPS is the server-side encode rate.

For per-second stage timings, output bitrate, active path (`gpu-compute`,
`gpu-fragment`, `gpu-hybrid`, or `software`), and `EGLImage` cache hit rate,
enable `QT_LOGGING_RULES="kpipewire_record_framestatistics.debug=true"`.
The log includes per-window p95 CPU time in milliseconds for the DMA-BUF fence
wait and the CUDA map and unmap calls. A value of `-1.000` means the window had
no samples for that stage. The CUDA timings measure host call duration.

## Tuning environment variables

All variables are optional and can be exported in `50-nvenc.conf`:

- `KPIPEWIRE_NVENC_PRESET`: `p1`..`p7` (or `fast`/`medium`/`slow`). Defaults to `p1` (`Speed`), `p4` (`NoPreference`), `p6` (`Quality`), `p7` (`Size`).
- `KPIPEWIRE_NVENC_TUNE`: `ull`, `ll`, `hq`, or `lossless`. Defaults to `ull` (`Speed`), `ll` (`NoPreference`), `hq` (`Quality`/`Size`).
- `KPIPEWIRE_NVENC_CQ`: `1`..`51` initial constant-quality target (default mapped from `setQuality`, or `25`). Runtime `setQuality()` calls dynamically reconfigure NVENC VBR/VBV bitrate live.
- `KPIPEWIRE_NVENC_MAXRATE`: VBV max bitrate cap (e.g. `25M`, `15000k`, or bits/s). Uncapped by default.
- `KPIPEWIRE_NVENC_GOP`: Keyframe interval in frames (default `100`).
- `KPIPEWIRE_NVENC_INTRA_REFRESH`: Set to `1` to enable periodic intra-refresh instead of IDR spikes.
- `KPIPEWIRE_NVENC_SPATIAL_AQ`: Enabled (`1`) by default for sharper desktop text; set to `0` to disable.
- `KPIPEWIRE_NVENC_NO_ZEROCOPY`: Set to `1` to disable the GPU DMA-BUF → GL → CUDA path and use the pooled software upload fallback.
