#!/usr/bin/env bash
set -euo pipefail

ISO="${1:?usage: test-uefi-qemu.sh path/to/research-os.iso}"
if [[ ! -s "$ISO" ]]; then
  echo "ISO is missing or empty: $ISO" >&2
  exit 2
fi

OVMF_CODE="${OVMF_CODE:-}"
if [[ -z "$OVMF_CODE" ]]; then
  for candidate in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd; do
    if [[ -s "$candidate" ]]; then OVMF_CODE="$candidate"; break; fi
  done
fi
if [[ -z "$OVMF_CODE" || ! -s "$OVMF_CODE" ]]; then
  echo "OVMF UEFI firmware was not found." >&2
  exit 2
fi
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "qemu-system-x86_64 is required." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/serial.log"
set +e
timeout 180s qemu-system-x86_64 \
  -machine q35,accel=tcg \
  -m 4096 -smp 2 \
  -bios "$OVMF_CODE" \
  -cdrom "$ISO" \
  -boot order=d \
  -display none \
  -serial "file:$LOG" \
  -monitor none \
  -no-reboot
QEMU_STATUS=$?
set -e

# A live OS is expected to keep running; timeout is a successful harness stop
# only when the serial console proves the guest reached its Research OS login.
if [[ "$QEMU_STATUS" -ne 0 && "$QEMU_STATUS" -ne 124 ]]; then
  echo "QEMU exited unexpectedly: $QEMU_STATUS" >&2
  cat "$LOG" >&2 || true
  exit 1
fi
if ! grep -Eqi 'Research OS|login:' "$LOG"; then
  echo "UEFI guest did not reach the Research OS serial login." >&2
  cat "$LOG" >&2 || true
  exit 1
fi

echo "RESEARCH_OS_QEMU_UEFI_BOOT=PASS"
