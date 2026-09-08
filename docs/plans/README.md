# Implementation plans — session 6 provisioning review

Each file is a self-contained task: context, exact changes, verification, and
rollback. They are written to be executed one at a time, in separate sessions,
without re-deriving the research.

Findings are tagged `S6-n` and cross-referenced from `STATE.md`.

## Order and dependencies

```
01-makefile-and-docs      ── DONE, verified (0ee2d6e)
02-nfs-and-setup-scripts  ── DONE, verified on all 3 nodes (0a2bf31)
03-k3s-config-migration   ── independent, touches control plane (restart)
04-cert-manager-upgrade   ── BLOCKS 05
05-k3s-136-upgrade        ── requires 04
06-ubuntu-lts-upgrade     ── do after 05; workers first, alphapi last
```

**01 and 02 are done.** Everything remaining is high risk and mutates live
cluster or node state — there is no cheap next step. 03 is the next in order.

**04 must precede 05.** cert-manager 1.14.5 does not support Kubernetes 1.36
(see 04 for the verified support matrix). Upgrading k3s first would run the
component that issues every TLS cert in the cluster outside its supported range.

## Before anything that touches a node

Confirm SSH with the real thing, not the agent:

```
$ ssh gabeduke@alphapi true && echo ok
```

`ssh-add -l` reporting "The agent has no identities" is **not** a blocker on its
own — session 7 confirmed the on-disk key is used directly and all three nodes
were reachable with an empty agent.

## Prior-session context

`STATE.md` holds the running history. `docs/tls-http01-outage.md` documents the
session-3 TLS outage, which plan 03 argues was probably caused by the bug it fixes.
