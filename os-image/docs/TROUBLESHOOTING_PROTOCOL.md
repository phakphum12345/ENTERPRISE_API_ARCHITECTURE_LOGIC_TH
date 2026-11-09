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

The Debian Live Manual documents binary hooks as running after the other binary commands and before `binary_checksums`. The Debian live-build GRUB configuration source sets `_TARGET="binary/boot/grub"`, creates that directory, copies templates there, and modifies matching `*.cfg` files. These facts mean the current failure must be investigated as a mismatch between the actual generated GRUB files/working directory and the hook's hard-coded single-file assumption. Do not repeat the unsupported claim that the binary hook ran before `binary_grub_cfg`.

References used for this incident:
- https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-contents.en.html
- https://sources.debian.org/src/live-build/1%3A20230502/scripts/build/binary_grub_cfg/
- https://packages.debian.org/source/trixie/live-build
- https://www.gnu.org/software/grub/manual/grub/
