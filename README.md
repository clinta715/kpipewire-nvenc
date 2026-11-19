# KPipeWire NVENC for KRdp

[nvenc-6.8.3.patch](nvenc-6.8.3.patch) adds NVIDIA hardware H.264 encoding
to KPipeWire 6.8.3 via FFmpeg's `h264_nvenc`. It also fixes frame pacing
when capture timestamps are rounded to milliseconds. Capture, pacing, and
the encoder use the configured maximum frame rate from startup.

The encoder still converts frames to YUV420P in system memory. For DMA-BUF
capture, this means a GPU readback before FFmpeg uploads frames to NVENC.

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

The drop-in selects the patched library and forces `h264_nvenc` while
`/usr/lib/libKPipeWireRecord.so.6` resolves to
`/usr/lib/libKPipeWireRecord.so.6.8.3`. If that version check fails,
KRdp starts with the system library. Port the patch and update the drop-in
before using it with another KPipeWire version.

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
