# Research OS Troubleshooting Protocol

**Protocol ID:** ROS-OSIMG-TROUBLESHOOTING-001  
**Applies to:** `os-image/`, Linux image CI, GRUB/UEFI boot validation, QEMU/OVMF, image provenance and release gates  
**Required workflow:** READ → ANALYZE → PLAN → MODIFY → TEST → AUDIT  
**Default posture:** fail closed; preserve existing data; never bypass a failing validation to obtain a green result.

## 1. Mandatory trigger

This protocol is mandatory whenever any of the following occurs:

- A CI job, required check, build step, test, boot test, artifact validation, checksum, SBOM, or release gate fails, times out, is cancelled, or produces ambiguous evidence.
- A proposed fix depends on undocumented assumptions about tool behavior, file paths, execution order, package contents, firmware, or runner environment.
- A previous attempted fix did not resolve the failure.

Do not immediately edit code after seeing a failure. First complete the evidence and documentation review below.

## 2. READ — collect primary evidence

For the exact failing run and commit SHA:

1. Record repository, PR, branch, head SHA, workflow name, run ID, job ID, runner OS/image, timestamps, and tool versions.
2. Fetch the complete failing job log, including the first error and preceding commands. Do not diagnose from the final exit code alone.
3. Identify the first failing command and distinguish the root failure from later skipped jobs or downstream symptoms.
4. Read the current versions of every relevant repository file and the complete workflow step that invokes it.
5. Compare the failing SHA with the current PR head before making any change. Never apply a fix based on stale logs without stating that limitation.

## 3. Documentation-first research

Read all documentation relevant to the failing layer, not merely the first search result. Prefer sources in this order:

1. Official documentation/manual for the exact tool and major/minor version used by CI.
2. Official upstream source code for the exact package release or tag installed by CI.
3. Official distribution package metadata, changelog, release notes, and man pages.
4. Official firmware/emulator documentation for the exact interfaces used.
5. Reputable issue reports only when official documentation and source do not explain the observed behavior. Treat issues as corroboration, not specification.

For each failure, create a short documentation matrix in the PR description or a linked investigation note:

| Field | Required evidence |
|---|---|
| Failing layer | Exact command, step, component |
| Installed version | Actual version from the failing runner/log |
| Documentation | Official URL and section/heading |
| Source verification | Exact release/tag source path when behavior is implementation-specific |
| Expected behavior | What the docs/source say should happen |
| Observed behavior | What the log and filesystem/artifact show |
| Difference | The specific mismatch that explains the failure |
| Fix implication | Smallest compliant change and regression test |

Search broadly enough to cover the complete failure path and its dependencies. Examples:
- Debian Live/live-build: Live Manual, relevant `lb(1)`/stage man pages, hook documentation, exact Trixie package source, package changelog, and configuration examples.
- GRUB: GNU GRUB manual for configuration, terminal, serial, EFI platform, and boot behavior; distro GRUB package documentation/source.
- UEFI/OVMF/QEMU: QEMU System Emulator documentation, OVMF/EDK II documentation and package layout, firmware CODE/VARS pairing, machine and boot-device semantics.
- Linux boot: kernel parameters documentation, initramfs/live-boot/live-config documentation, serial console documentation.
- Artifact integrity: CycloneDX specification, SHA-256 tool documentation, ISO/xorriso documentation, and GitHub Actions artifact/check documentation.
- Workflow orchestration: GitHub Actions workflow syntax, job dependencies, permissions, concurrency, artifacts, and required-check semantics.

Do not claim “all docs” were read unless the investigation note lists the actual sources and sections reviewed. When the exact installed version is unavailable from the log, add a version-reporting step before relying on version-sensitive behavior.

## 4. ANALYZE — prove the root cause

- Reconstruct the actual execution order from logs and source code. Do not infer order from filenames or hook numbering.
- Verify working directory, path roots, symlinks, file existence, permissions, ownership, environment variables, and whether a command runs in the host, chroot, container, or guest.
- Distinguish documented guarantees from implementation details and assumptions.
- Use the exact runner package version. If a source mirror only exposes another release, label it as comparative evidence and do not present it as proof of the runner's exact implementation.
- State root cause with at least one direct log observation and one corroborating documentation/source observation.
- If evidence is insufficient, add diagnostic instrumentation or a minimal reproduction first. Do not guess.

## 5. PLAN before MODIFY

Write down:
- Root cause and evidence.
- Files expected to change and why.
- Expected behavior after the fix.
- Positive test(s), negative test(s), and regression test(s).
- Safety impact and rollback approach.
- CI jobs expected to run and artifacts expected to be produced.

Keep the patch minimal. Do not combine unrelated cleanup with a failure fix unless the unrelated defect blocks validation; if discovered, document and isolate it.

## 6. MODIFY — safety constraints

- Preserve user data, existing application behavior, repository boundaries, and release scope.
- Never disable a failing test, weaken an assertion, mask an exit code, ignore an error, or mark a job successful without proving the underlying requirement.
- Never replace a real boot test with a static assertion and call it boot validation.
- Do not write to physical USB media, internal disks, EFI System Partitions, or firmware variables as part of CI troubleshooting.
- Do not change BIOS, Secure Boot, VMD, or hardware configuration without separate explicit authorization.
- Keep live-image and installer scopes separate. This milestone remains live-only unless a separately reviewed installer project is authorized.

## 7. TEST — evidence required

Run applicable static checks and targeted regression tests first, then the full CI workflow. The CI run must reference the exact resulting commit SHA.

For the Linux Live Image milestone, keep these results distinct:

1. Python build-contract tests and shell syntax.
2. Debian Trixie live-build completes and produces a non-empty ISO.
3. ISO structure contains kernel, initramfs, and SquashFS payload.
4. BIOS/UEFI bootloader files and GRUB configuration are present and internally consistent.
5. QEMU/OVMF boots the actual ISO through firmware and reaches the expected live boot milestone; serial output must identify the stage reached.
6. Live environment reaches the expected login/session milestone; a GRUB menu alone is not a successful OS boot.
7. SHA-256 verification succeeds against the final artifact.
8. Package inventory, CycloneDX SBOM, and build metadata are valid and mutually consistent.
9. Artifact upload succeeds and the uploaded artifact can be retrieved/inspected.
10. Final Gate and all repository Required Checks pass on the same latest PR head SHA.

A skipped downstream step is not a pass. A successful static test is not proof of runtime boot. A QEMU pass is not physical hardware qualification.

## 8. AUDIT and merge gate

Before merge, verify:

- PR is still open and targets the intended base branch.
- Latest head SHA is the SHA whose CI results are being audited.
- No newer commit has invalidated the checks.
- Every Required Check has a successful conclusion. Pending, failed, cancelled, abandoned, skipped-required, missing, or unknown results are not green.
- Final Gate is successful.
- ISO, checksum, SBOM, package inventory, metadata, and uploaded artifact correspond to the same build/source SHA.
- PR diff contains only reviewed changes; no accidental generated files, secrets, or unsafe disk-write commands.
- Mergeability and branch protection are rechecked immediately before merge.

If any condition is not met, keep the PR unmerged and report the exact blocker.

## 9. Failure investigation record template

Copy this template for each failure:

```text
Protocol ID:
Repository / PR:
Failing commit SHA:
Workflow / run ID / job ID:
Runner image:
Tool and exact version:
First failing command:
First error (verbatim):
Relevant files and paths:
Official docs reviewed (URL + section):
Exact-version source reviewed:
Expected behavior:
Observed behavior:
Root cause:
Fix plan:
Regression tests:
CI run for fix SHA:
Artifact / checksum / SBOM evidence:
Required-check audit:
Merge decision: BLOCKED / ELIGIBLE
```

## 10. Initial references for the current Debian Live ISO / UEFI work

These are starting points, not a substitute for checking the exact installed package version and all relevant sections:

- Debian Live Manual — https://live-team.pages.debian.net/live-manual/
- Debian Live Manual, customizing contents and hook stages — https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-contents.en.html
- Debian Trixie live-build package/source version — https://packages.debian.org/source/trixie/live-build
- Debian live-build source browser — https://sources.debian.org/src/live-build/
- GNU GRUB Manual — https://www.gnu.org/software/grub/manual/grub/
- GNU GRUB serial command — https://www.gnu.org/software/grub/manual/grub/html_node/serial.html
- GNU GRUB serial terminal — https://www.gnu.org/software/grub/manual/grub/html_node/Serial-terminal.html
- QEMU System Emulator invocation — https://www.qemu.org/docs/master/system/invocation.html
- TianoCore EDK II / OVMF documentation — https://github.com/tianocore/edk2

## 11. Current incident note — PR #46

The failing log for the Linux ISO job shows:
- `lb binary_grub_cfg` ran before `lb binary_hooks`.
- The hook was invoked and exited because it could not find `binary/boot/grub/grub.cfg`.
- The job stopped at the hook; UEFI/QEMU boot, checksum, SBOM, and artifact upload were not reached in that run.

The Debian Live Manual documents binary hooks as running after the other binary commands and before `binary_checksums`. The exact Debian Trixie `live-build 1:20250505+deb13u1` source shows that `binary_grub_cfg` sets `_TARGET="binary/boot/grub"`, creates that directory, copies GRUB templates there, and edits matching `*.cfg` files. The exact Trixie `binary_hooks` source then runs `cd binary` before executing the hook. Therefore, paths inside a binary hook are relative to the `binary/` directory: the hook's old `binary/boot/grub/grub.cfg` resolved to the incorrect nested path `binary/binary/boot/grub/grub.cfg`. The correct relative path is `boot/grub/grub.cfg` (subject to verifying the expected file exists in the generated image). The immediate failure was a working-directory/path-root mismatch, not hook ordering. Do not repeat the unsupported claim that the binary hook ran before `binary_grub_cfg`.

A subsequent source audit also found a separate build-output correctness issue: the package inventory format had doubled escape characters for tab/newline delimiters, while the metadata writer emitted a literal backslash-n instead of a real line feed. The build script and build-contract tests were corrected to require actual delimiters/newlines. These were discovered during the broader output-integrity audit; they are not the cause of the original hook failure.

References used for this incident:
- https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-contents.en.html
- https://sources.debian.org/src/live-build/1%3A20250505%2Bdeb13u1/scripts/build/binary_grub_cfg
- https://sources.debian.org/src/live-build/1%3A20250505%2Bdeb13u1/scripts/build/binary_hooks
- https://sources.debian.org/src/live-build/1%3A20230502/scripts/build/binary_grub_cfg/
- https://packages.debian.org/source/trixie/live-build
- https://www.gnu.org/software/grub/manual/grub/


## 12. Current incident note — PR #46 UEFI/QEMU boot timeout

**Evidence target:** PR #46, head `26bdbd6b38c6d6b1cffab14872dc693c1ea7e868`, workflow run `42597860285`, job `129097184369`.

### Observed facts

- The Debian Trixie live-build completed and produced `research-os-amd64.iso` (1,249,683,456 bytes).
- The build metadata and checksums were emitted. The job then installed QEMU/OVMF and ran the real ISO with `qemu-system-x86_64`.
- The runner reported OVMF CODE `/usr/share/OVMF/OVMF_CODE_4M.fd` and VARS `/usr/share/OVMF/OVMF_VARS_4M.fd`.
- QEMU ran for the full 180-second timeout. The captured serial log contained OVMF messages including `BdsDxe: starting Boot0002 "UEFI QEMU DVD-ROM"`, but no GRUB serial marker, Linux kernel banner, or Research OS live-session/login marker.
- This proves the firmware selected the UEFI DVD boot entry. It does **not** prove that GRUB produced serial output, that the Linux kernel started, or that the live userspace/desktop started.
- Exact versions visible in the failing build log: `live-build 1:20250505+deb13u1`; `grub-common 2.12-9+deb13u2`; `grub-efi-amd64-bin 2.12-9+deb13u2`; `grub-efi-amd64-signed 1+2.12+9+deb13u2`; QEMU `1:10.2.1+ds-1ubuntu3.3`; OVMF package `2025.11-3ubuntu7.3`.

### Documentation matrix

| Layer | Exact source and documented behavior | Observed evidence / implication |
|---|---|---|
| GRUB serial | GNU GRUB 2.12 Manual, serial and serial terminal sections: `https://www.gnu.org/software/grub/manual/grub/grub.html`. The serial device is initialized with `serial`; it is only used for communication after `terminal_input` or `terminal_output` selects it. | The hook called these commands but did not explicitly load the corresponding modules. The next build now loads them explicitly and emits a unique serial marker. |
| GRUB modules | Debian Trixie `grub-efi-amd64-bin 2.12-9+deb13u2` file list: `https://packages.debian.org/trixie/amd64/grub-efi-amd64-bin/filelist`. It contains `serial.mod` and `terminal.mod` under `/usr/lib/grub/x86_64-efi/`. | The package has the modules, but the failed ISO was not uploaded in that run, so their presence and location inside that exact ISO were not independently inspected. The build now searches the ISO for both modules and records their paths. |
| Linux serial console | Linux kernel Serial Console documentation: `https://docs.kernel.org/admin-guide/serial-console.html`. Kernel output uses a `console=device,options` parameter such as `console=ttyS0,115200n8`. | The image passes `console=ttyS0,115200n8`; the next run must show a Linux/userspace marker, not merely OVMF output. |
| Debian Live | Debian Trixie `live-boot(7)`: `https://manpages.debian.org/trixie/live-boot-doc/live-boot.7.en.html`. It documents `console=TTY,SPEED` for the live-getty console. | The image configures ttyS0 and explicitly enables `serial-getty@ttyS0.service`; a separate graphical readiness marker now checks that the display manager is active. |
| systemd getty | Debian Trixie `systemd-getty-generator(8)`: `https://manpages.debian.org/trixie/systemd/systemd-getty-generator.8.en.html`. The kernel `console=` parameter can cause a serial getty to be generated. | This corroborates the serial-login path but does not by itself prove the desktop started. |
| QEMU serial capture | QEMU System Emulator invocation documentation: `https://www.qemu.org/docs/master/system/invocation.html`. Character devices can route guest serial traffic to a host file backend. | QEMU's `-serial file:$LOG` captured OVMF output, so the host-side serial log file was connected. The next run also saves QEMU guest-error/CPU-reset diagnostics. |

### Working hypothesis — not yet a proven root cause

The current best-supported hypothesis is that the GRUB EFI configuration attempted to use the `serial` and `terminal_input/output` commands without explicitly loading their dynamically loadable modules. Debian's exact Trixie package contains `serial.mod` and `terminal.mod`, and the GRUB manual describes the required serial initialization and terminal selection sequence. The previous log cannot prove this was the sole cause because the actual failed ISO was not retained and no GRUB output was captured.

### Minimal correction and regression evidence

The next patch:

1. Explicitly runs `insmod serial` and `insmod terminal` before initializing/selecting the serial terminal.
2. Emits `RESEARCH_OS_GRUB_SERIAL=READY` only after GRUB selects the serial terminal.
3. Requires a separate `RESEARCH_OS_LIVE_READY=1` marker after systemd confirms `display-manager.service` is active; the marker is conditional on `/dev/ttyS0` and does not change normal hardware boot behavior.
4. Verifies that the built ISO actually contains `serial.mod` and `terminal.mod`, and records the exact GRUB package versions in build metadata.
5. Saves QEMU guest-error/CPU-reset diagnostics and uploads the ISO plus provenance even when the boot smoke test fails.

The new test is staged, not yet proven: the next CI run on the resulting commit SHA must show both markers and a successful QEMU timeout-as-expected result. If the GRUB marker is absent, inspect the retained ISO's GRUB config/module paths and QEMU debug log. If the GRUB marker is present but the live marker is absent, investigate the kernel command line, live-boot discovery, serial getty, systemd target, and display-manager startup separately. Do not collapse these into a generic "QEMU failed" diagnosis.

### Sources reviewed

- GNU GRUB 2.12 Manual — `https://www.gnu.org/software/grub/manual/grub/grub.html`
- Debian Trixie GRUB EFI AMD64 package file list — `https://packages.debian.org/trixie/amd64/grub-efi-amd64-bin/filelist`
- Linux Kernel Serial Console — `https://docs.kernel.org/admin-guide/serial-console.html`
- Debian Trixie live-boot(7) — `https://manpages.debian.org/trixie/live-boot-doc/live-boot.7.en.html`
- Debian Trixie systemd-getty-generator(8) — `https://manpages.debian.org/trixie/systemd/systemd-getty-generator.8.en.html`
- QEMU System Emulator invocation — `https://www.qemu.org/docs/master/system/invocation.html`
- xorriso(1), ISO tree traversal with `-find` — `https://manpages.debian.org/unstable/xorriso/xorriso.1.en.html`
