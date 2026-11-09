# Research OS Linux Live Image

**Artifact:** Research OS x86_64 UEFI Live ISO  
**Version:** 0.1.0-dev  
**Base:** Debian Live (Trixie) with the distribution Linux kernel  
**Status:** Initial image foundation; not a production release

## Scope

This subproject builds an independently bootable live ISO for x86_64 UEFI systems. It assembles a Linux kernel, initramfs, compressed live root filesystem, GRUB boot paths, a minimal XFCE desktop, and hardware inspection tools. The build uses Debian Live tooling and pinned distribution suite selection; package versions and build provenance are recorded in the artifact metadata.

The first milestone is a **live environment**, not an installer to an internal disk. It must not repartition, format, or install to a disk. An installation workflow, update/recovery strategy, Research OS Control Center integration, and hardware qualification are separate gates and are not claimed complete here.

## Build

Run inside a clean Debian Trixie environment as root:

```bash
./build.sh
```

Outputs are written to `dist/`:
- `research-os-amd64.iso`
- `SHA256SUMS`
- `build-metadata.json`
- `SBOM-packages.txt` (installed package inventory)
- `iso-live-contents.txt`

The script does not write to USB devices or internal disks.

## Boot and hardware validation

- CI verifies ISO-9660 structure, kernel, initramfs, squashfs payload, checksum, build metadata, package inventory, and a QEMU/OVMF UEFI boot reaching the Research OS serial login.
- QEMU/OVMF boot validation is a separate gate and must be reported separately from static image checks.
- Physical ASUS Vivobook X1504VA validation is required before claiming hardware compatibility.
- MediaTek MT7902, Intel UHD acceleration, VMD/storage, audio, touchpad, Wi-Fi, suspend, and power management remain unqualified until measured.

## Security and safety

- No disk installer or automatic disk mutation is included.
- No secrets or credentials are baked into the image.
- Third-party packages come from configured Debian repositories and retain their upstream licenses.
- The kernel is the distribution-provided Linux kernel; this is not a claim that a new kernel was written from scratch.
- Do not use this ISO to modify the internal disk until a separately reviewed installer exists.
