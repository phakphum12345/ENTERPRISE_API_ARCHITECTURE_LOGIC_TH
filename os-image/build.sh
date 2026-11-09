#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Research OS image build must run as root in an isolated build container." >&2
  exit 2
fi

DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
SOURCE_SHA="${SOURCE_SHA:-UNPINNED}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
export SOURCE_DATE_EPOCH

case "$DEBIAN_SUITE" in
  trixie) ;;
  *) echo "Unsupported Debian suite: $DEBIAN_SUITE" >&2; exit 2 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  debootstrap \
  live-build \
  xorriso \
  squashfs-tools \
  dosfstools \
  mtools \
  grub-pc-bin \
  grub-efi-amd64-bin \
  grub-efi-amd64-signed \
  isolinux \
  syslinux-common \
  syslinux-utils \
  python3 \
  file \
  dpkg-dev

test -f config/package-lists/researchos.list.chroot
test -f config/includes.chroot/etc/os-release
lb clean --purge

lb config \
  --distribution "$DEBIAN_SUITE" \
  --architectures amd64 \
  --binary-images iso-hybrid \
  --bootloaders "grub-pc,grub-efi" \
  --archive-areas "main contrib non-free-firmware" \
  --apt-recommends false \
  --debian-installer none \
  --checksums sha256 \
  --iso-application "Research OS" \
  --iso-publisher "Research OS Project" \
  --iso-volume "RESEARCH_OS_010" \
  --bootappend-live "boot=live components hostname=researchos username=researchos console=ttyS0,115200n8" \
  --uefi-secure-boot auto

# Ensure the binary hook is executable; live-build also enforces this
# when invoking hooks, but set the mode explicitly for reproducible intent.
chmod 0755 config/hooks/live/0200-enable-grub-serial-output.hook.binary
lb build

# live-build writes the binary ISO in the project working directory
# (for example, live-image-amd64.hybrid.iso), not under binary/.
# Accept the documented root output and the binary/ layout used by some
# live-build configurations, while excluding our own dist/ copy.
DIST="$ROOT/dist"
mkdir -p "$DIST"
ISO_SOURCE="$(find "$ROOT" -maxdepth 2 -type f -name '*.iso' \
  ! -path "$DIST/*" -print -quit)"
if [[ -z "$ISO_SOURCE" || ! -s "$ISO_SOURCE" ]]; then
  echo "live-build did not produce a non-empty ISO image in $ROOT or $ROOT/binary." >&2
  find "$ROOT" -maxdepth 2 -type f -name '*.iso' -print >&2 || true
  exit 1
fi

cp -- "$ISO_SOURCE" "$DIST/research-os-amd64.iso"
xorriso -indev "$DIST/research-os-amd64.iso" -ls /live > "$DIST/iso-live-contents.txt" 2>&1
grep -Eq 'vmlinuz' "$DIST/iso-live-contents.txt"
grep -Eq 'initrd' "$DIST/iso-live-contents.txt"
grep -Eq 'filesystem.squashfs' "$DIST/iso-live-contents.txt"

(
  cd "$DIST"
  sha256sum research-os-amd64.iso > SHA256SUMS
  chroot "$ROOT/chroot" dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > PACKAGE-INVENTORY.txt
)

python3 - "$DIST/SBOM.cdx.json" "$DIST/PACKAGE-INVENTORY.txt" "$SOURCE_SHA" "$SOURCE_DATE_EPOCH" <<'PY'
import hashlib
import json
import pathlib
import sys
import uuid
from datetime import datetime, timezone
from urllib.parse import quote

output, inventory_path, source_sha, epoch = sys.argv[1:]
inventory = pathlib.Path(inventory_path).read_text(encoding="utf-8").splitlines()
components = []
for line in inventory:
    if not line.strip():
        continue
    name, version = line.split(chr(9), 1)
    package_name, _, architecture = name.partition(":")
    purl = "pkg:deb/debian/" + quote(package_name, safe=".+-") + "@" + quote(version, safe=".+-")
    if architecture:
        purl += "?arch=" + quote(architecture, safe=".+-")
    components.append({
        "type": "library",
        "name": package_name,
        "version": version,
        "purl": purl,
        "scope": "required",
    })
inventory_sha = hashlib.sha256(pathlib.Path(inventory_path).read_bytes()).hexdigest()
serial = uuid.uuid5(uuid.NAMESPACE_URL, "research-os:" + source_sha + ":" + inventory_sha)
timestamp = datetime.fromtimestamp(int(epoch), timezone.utc).isoformat().replace("+00:00", "Z")
bom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": "urn:uuid:" + str(serial),
    "version": 1,
    "metadata": {
        "timestamp": timestamp,
        "component": {
            "type": "operating-system",
            "name": "Research OS",
            "version": "0.1.0-dev",
        },
        "properties": [
            {"name": "researchos:source-sha", "value": source_sha},
            {"name": "researchos:base-suite", "value": "trixie"},
        ],
    },
    "components": components,
}
pathlib.Path(output).write_text(json.dumps(bom, indent=2, sort_keys=True) + chr(10), encoding="utf-8")
PY

python3 - "$DIST/build-metadata.json" "$DEBIAN_SUITE" "$SOURCE_SHA" "$SOURCE_DATE_EPOCH" "$DIST/research-os-amd64.iso" <<'PY'
import hashlib
import json
import pathlib
import sys

output, suite, source_sha, epoch, artifact = sys.argv[1:]
path = pathlib.Path(artifact)
digest = hashlib.sha256()
with path.open("rb") as stream:
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(chunk)
digest = digest.hexdigest()
metadata = {
    "schema_version": "1.0",
    "product": "Research OS",
    "version": "0.1.0-dev",
    "artifact": path.name,
    "architecture": "amd64",
    "boot_mode": ["uefi", "bios"],
    "image_type": "live-iso-hybrid",
    "base_distribution": "Debian",
    "distribution_suite": suite,
    "kernel": "Debian linux-image-amd64 package",
    "root_filesystem": "Debian Live squashfs",
    "installer": "not-included",
    "source_sha": source_sha,
    "source_date_epoch": int(epoch),
    "live_build_version": __import__("subprocess").check_output(["lb", "--version"], text=True).strip(),
    "package_inventory": "PACKAGE-INVENTORY.txt",
    "sbom": "SBOM.cdx.json",
    "sbom_sha256": hashlib.sha256(pathlib.Path("dist/SBOM.cdx.json").read_bytes()).hexdigest(),
    "package_inventory_sha256": hashlib.sha256(pathlib.Path("dist/PACKAGE-INVENTORY.txt").read_bytes()).hexdigest(),
    "size_bytes": path.stat().st_size,
    "sha256": digest,
    "hardware_qualification": "not-performed",
    "scope": "live image build metadata; not proof of boot or hardware compatibility",
}
pathlib.Path(output).write_text(json.dumps(metadata, indent=2, sort_keys=True) + chr(10), encoding="utf-8")
PY

echo "RESEARCH_OS_ISO_BUILD=PASS"
cat "$DIST/build-metadata.json"
