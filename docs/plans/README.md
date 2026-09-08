# Implementation plans — session 6 provisioning review

Each file is a self-contained task: context, exact changes, verification, and
rollback. They are written to be executed one at a time, in separate sessions,
without re-deriving the research.

Findings are tagged `S6-n` and cross-referenced from `STATE.md`.

## Order and dependencies

```
01-makefile-and-docs      ── independent, repo-only, zero cluster impact
02-nfs-and-setup-scripts  ── DONE, verified on all 3 nodes (uncommitted)
03-k3s-config-migration   ── independent, touches control plane (restart)
04-cert-manager-upgrade   ── BLOCKS 05
05-k3s-136-upgrade        ── requires 04
06-ubuntu-lts-upgrade     ── do after 05; workers first, alphapi last
```

**Do 01 and 02 first.** They are cheap, carry no cluster risk, and 02 removes a
false-success bug that is currently hiding the real state of NFS on the nodes.

**04 must precede 05.** cert-manager 1.14.5 does not support Kubernetes 1.36
(see 04 for the verified support matrix). Upgrading k3s first would run the
component that issues every TLS cert in the cluster outside its supported range.

## Blocker for everything that touches a node

SSH from the workstation is currently broken:

```
$ ssh-add -l
The agent has no identities
```

Run `ssh-add` (and confirm `ssh gabeduke@alphapi true` succeeds) before starting
02, 03, 05, or 06. Plan 01 is the only one that works without it.

## Prior-session context

`STATE.md` holds the running history. `docs/tls-http01-outage.md` documents the
session-3 TLS outage, which plan 03 argues was probably caused by the bug it fixes.
