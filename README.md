# hd-lima-image

Golden rootfs image for **Hydrogen Desktop on macOS**.

The macOS build runs the workspace as a `systemd-nspawn` machine inside an HD-owned
Lima utility VM (Apple Virtualization.framework, arm64 + Rosetta). This repo's releases
host the arm64 **Rosetta-hybrid** golden rootfs the app downloads on first launch
(native arm64 code-server/node/claude + x86-64 Adom CLIs under Rosetta).

Sibling of [`hd-wsl2-image`](https://github.com/adom-inc/hd-wsl2-image) (the Windows/WSL2
x86-64 image). Release assets: `adom-golden-<version>-arm64.tar.gz` + `.sha256`.