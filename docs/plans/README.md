# Implementation plans

Each file is a self-contained task: context, exact changes, verification, and
rollback. They are written to be executed one at a time, in separate sessions,
without re-deriving the research.

Plans 01-06 came out of the session-6 provisioning review; their findings are
tagged `S6-n`. Plan 07 was found separately, while decommissioning the stale
gift-wiki deployment.

## Order and dependencies

```
01-makefile-and-docs      ── DONE, verified (0ee2d6e)
02-nfs-and-setup-scripts  ── DONE, verified on all 3 nodes (0a2bf31)
03-k3s-config-migration   ── DONE, verified 2026-09-08
04-cert-manager-upgrade   ── BLOCKS 05
05-k3s-136-upgrade        ── requires 04
06-ubuntu-lts-upgrade     ── do after 05; workers first, alphapi last
07-dns-endpoints-namespace ── independent, low risk, docs+manifests only
```

**01, 02 and 03 are done.** Of what remains, 04-06 are high risk and mutate
live cluster or node state; **04 is next in that order**. **07 is the one cheap
item** — additive manifests plus a namespace, safe because external-dns runs
`policy: upsert-only`. It can be done at any time, independently, and is a good
choice if you want progress without a maintenance window.

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

`STATE.md` holds the running history (untracked — see `CLAUDE.md`).
`docs/tls-http01-outage.md` documents the session-3 TLS outage. Plan 03
originally argued that outage was probably caused by the bug it fixes; that is
**wrong** and plan 03's *Outcome* section explains why — the k3s serving cert
accumulates SANs and never drops them, so the dropped `alphapi` SAN kept being
served.
