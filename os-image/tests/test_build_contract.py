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
        self.assertIn("chmod 0755 config/hooks/live/0200-enable-grub-serial-output.hook.binary", script)

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
        self.assertIn('-find / -name serial.mod', script)
        self.assertIn('-find / -name terminal.mod', script)
        self.assertIn('grub-efi-package-version', script.lower())
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
        self.assertIn("RESEARCH_OS_GRUB_SERIAL=READY", script)
        self.assertIn("RESEARCH_OS_LIVE_READY=1", script)
        self.assertIn("qemu-debug.log", script)
        self.assertIn('cp -- "$OVMF_VARS" "$WORK/OVMF_VARS.fd"', script)
        self.assertIn('-drive if=pflash,format=raw,unit=0,readonly=on,file="$OVMF_CODE"', script)
        self.assertIn('-drive if=pflash,format=raw,unit=1,file="$WORK/OVMF_VARS.fd"', script)
        self.assertNotIn('-bios "$OVMF_CODE"', script)

    def test_grub_serial_output_is_enabled_without_disabling_video_console(self):
        hook = (ROOT / "config/hooks/live/0200-enable-grub-serial-output.hook.binary").read_text(encoding="utf-8")
        self.assertIn('GRUB_CONFIG="boot/grub/grub.cfg"', hook)
        self.assertNotIn('GRUB_CONFIG="binary/boot/grub/grub.cfg"', hook)
        self.assertLess(hook.index("insmod serial"), hook.index("serial --unit=0"))
        self.assertLess(hook.index("insmod terminal"), hook.index("terminal_input console serial"))
        self.assertIn("serial --unit=0 --speed=115200", hook)
        self.assertIn("terminal_input console serial", hook)
        self.assertIn("terminal_output console serial", hook)
        self.assertIn("RESEARCH_OS_GRUB_SERIAL=READY", hook)
        self.assertIn('cat "$GRUB_CONFIG"', hook)


    def test_live_graphical_readiness_marker_is_conditioned_on_display_manager(self):
        service = (ROOT / "config/includes.chroot/etc/systemd/system/research-os-live-ready.service").read_text(encoding="utf-8")
        hook = (ROOT / "config/hooks/live/0150-enable-live-ready-marker.hook.chroot").read_text(encoding="utf-8")
        self.assertIn("ConditionPathExists=/dev/ttyS0", service)
        self.assertIn("After=display-manager.service", service)
        self.assertIn("systemctl is-active --quiet display-manager.service", service)
        self.assertIn("RESEARCH_OS_LIVE_READY=1", service)
        self.assertIn("graphical.target.wants", hook)
        self.assertIn("research-os-live-ready.service", hook)

    def test_package_inventory_and_metadata_use_real_delimiters(self):
        script = (ROOT / "build.sh").read_text(encoding="utf-8")
        self.assertIn(r"dpkg-query -W -f='${binary:Package}\t${Version}\n'", script)
        self.assertIn('json.dumps(metadata, indent=2, sort_keys=True) + chr(10)', script)
        self.assertIn('grub_efi_package_version', script)
        self.assertIn('grub_common_package_version', script)
        self.assertNotIn(r'json.dumps(metadata, indent=2, sort_keys=True) + "\\n"', script)

    def test_documentation_first_troubleshooting_protocol_is_present(self):
        protocol = (ROOT / "docs/TROUBLESHOOTING_PROTOCOL.md").read_text(encoding="utf-8")
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("READ → ANALYZE → PLAN → MODIFY → TEST → AUDIT", protocol)
        self.assertIn("binary_hooks", protocol)
        self.assertIn("cd binary", protocol)
        self.assertIn("TROUBLESHOOTING_PROTOCOL.md", readme)

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
