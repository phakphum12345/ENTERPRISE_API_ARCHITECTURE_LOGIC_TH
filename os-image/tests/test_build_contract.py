import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ResearchOSImageBuildContractTests(unittest.TestCase):
    def test_build_is_explicitly_x86_64_debian_live_and_uefi_capable(self):
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertIn("--distribution", script)
        self.assertIn("trixie", script)
        self.assertIn("--architectures amd64", script)
        self.assertIn("--binary-images iso-hybrid", script)
        self.assertIn("--bootloaders", script)
        self.assertIn("grub-efi", script)
        self.assertIn("--debian-installer none", script)
        self.assertIn("lb clean --purge", script)
        self.assertNotIn("lb clean --purge || true", script)

    def test_recommends_are_disabled_and_live_user_prerequisites_are_explicit(self):
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        packages = (ROOT / "config/package-lists/researchos.list.chroot").read_text(encoding="utf-8")
        self.assertIn("--apt-recommends false", script)
        self.assertIn("sudo", packages.splitlines())
        self.assertIn("user-setup", packages.splitlines())

    def test_iso_discovery_accepts_live_build_working_directory_output(self):
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertIn('find "$ROOT" -maxdepth 2 -type f -name', script)
        self.assertIn('! -path "$DIST/*"', script)
        self.assertIn('"$DIST/research-os-amd64.iso"', script)
        self.assertNotIn('find "$ROOT/binary" -maxdepth 1', script)

    def test_live_kernel_initramfs_and_rootfs_are_required(self):
        packages = (ROOT / "config/package-lists/researchos.list.chroot").read_text(encoding="utf-8")
        for package in ("linux-image-amd64", "live-boot", "live-config", "systemd-sysv"):
            self.assertIn(package, packages)
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        for payload in ("vmlinuz", "initrd", "filesystem.squashfs"):
            self.assertIn(payload, script)

    def test_first_milestone_does_not_enable_disk_installer(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertIn("not an installer", readme)
        self.assertIn("--debian-installer none", script)

    def test_uefi_smoke_test_discovers_runner_specific_ovmf_paths(self):
        script = (ROOT / "test-uefi-qemu.sh").read_text(encoding="utf-8")
        self.assertIn("/usr/share/edk2/ovmf/OVMF_CODE_4M.fd", script)
        self.assertIn("/usr/share/qemu/OVMF_CODE_4M.fd", script)
        self.assertIn("find /usr/share", script)
        self.assertIn("-type f -o -type l", script)
        self.assertIn("OVMF_CODE*.fd", script)
        self.assertIn('echo "Using OVMF CODE: $OVMF_CODE"', script)
        self.assertIn('echo "Using OVMF VARS template: $OVMF_VARS"', script)
        self.assertIn("OVMF_VARS_4M.fd", script)
        self.assertIn('cp -- "$OVMF_VARS" "$WORK/OVMF_VARS.fd"', script)
        self.assertIn('-drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE"', script)
        self.assertIn('-drive if=pflash,format=raw,unit=1,file="$WORK/OVMF_VARS.fd"', script)
        self.assertNotIn('-bios "$OVMF_CODE"', script)

    def test_grub_serial_output_is_enabled_without_disabling_video_console(self):
        hook = (ROOT / "config/hooks/live/0200-enable-grub-serial-output.hook.binary").read_text(encoding="utf-8")
        self.assertIn('GRUB_CONFIG="binary/boot/grub/grub.cfg"', hook)
        self.assertIn("serial --unit=0 --speed=115200", hook)
        self.assertIn("terminal_input console serial", hook)
        self.assertIn("terminal_output console serial", hook)
        self.assertIn('cat "$GRUB_CONFIG"', hook)

    def test_build_script_contains_no_physical_disk_write_commands(self):
        script = (ROOT / "build.sh").read_text(encoding="utf-8").lower()
        forbidden = (
            "dd if=",
            "mkfs.",
            "wipefs",
            "sgdisk",
            "parted ",
            "fdisk ",
            "efibootmgr --create",
            "mount /dev/",
        )
        for command in forbidden:
            self.assertNotIn(command, script)

    def test_branding_is_consistent_and_experimental(self):
        os_release = (ROOT / "config/includes.chroot/etc/os-release").read_text(encoding="utf-8")
        motd = (ROOT / "config/includes.chroot/etc/motd").read_text(encoding="utf-8")
        self.assertIn('ID=researchos', os_release)
        self.assertIn('VERSION_ID="0.1.0-dev"', os_release)
        self.assertIn("experimental", motd.lower())
        self.assertIn("not modified automatically", motd)


if __name__ == "__main__":
    unittest.main()
