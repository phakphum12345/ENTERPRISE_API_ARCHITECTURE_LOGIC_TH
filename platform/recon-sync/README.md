# Recon-Sync Platform

Long-term canonical synchronization control plane.

Commands: status, sync, verify, audit, evidence, recover.

The HTA is only a frontend adapter; the PowerShell engine is authoritative.

Safety invariants: no reset --hard, no git clean, no force-push, no history rewrite, no deletion of versions/, preserve dirty worktrees, create detached canonical worktrees, record evidence and hashes, fail closed on audit violations.
