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
04-cert-manager-upgrade   ── DONE, verified 2026-09-08
05-k3s-136-upgrade        ── DONE, verified 2026-09-08 (all 3 nodes v1.36.4+k3s1)
06-ubuntu-lts-upgrade     ── NEXT; workers first, alphapi last -- but read 05's
                             Outcome first: it also drains, and the two PDB
                             blockers 05 hit will stall it the same way
07-dns-endpoints-namespace ── independent, low risk, docs+manifests only
```

**01, 02, 03, 04 and 05 are done.** Of what remains, **06 is next** and is high
risk — it drains nodes and mutates node state.
**07 is the one cheap item** — additive manifests plus a namespace, safe because
external-dns runs `policy: upsert-only`. It can be done at any time,
independently, and is a good choice if you want progress without a maintenance
window.

### Before plan 06: clear the drain blockers plan 05 found

Plan 06 drains nodes, so it hits exactly what stalled plan 05 for ~45 minutes.
Fix these first or it will stall too — full detail in plan 05's *Outcome*:

- **`influxdb-influxdb2`** is a single-replica StatefulSet with a PDB of
  `minAvailable: 1`, so its pod can **never** be evicted and any drain of its node
  retries until the job's `activeDeadlineSeconds` kills it. It uses `emptyDir`, so
  the PDB protects nothing — give it a real PVC or drop the PDB.
- **`pvc-fc1353bc` (Prometheus) has one replica.** Longhorn's
  `block-if-contains-last-replica` then refuses to release that node's
  instance-manager, and detaching the volume is **not** enough. Give it a second
  replica.
- **Never `kubectl delete` a failed upgrade Job** without
  `kubectl -n system-upgrade rollout restart deploy/system-upgrade-controller`
  afterwards — it wedges the Plan on `status.applying` and nothing moves.

**Read plan 05's Outcome section before starting 06.** Four corrections, two of
which are the difference between a 10-minute node upgrade and a stalled one.
Plan 04's Outcome still carries the reusable technique: render both chart versions
and diff the object sets to turn "N minors is scary" into a countable fact;
never `kubectl apply` a repo Application file while auto-sync is deliberately
off; and there is no `argocd` CLI here, so syncs are triggered by patching the
Application's `operation` field.

## Before anything that touches a node

Confirm SSH with the real thing, not the agent:

```
$ ssh gabeduke@alphapi true && echo ok
```

`ssh-add -l` reporting "The agent has no identities" is **not** a blocker on its
own — session 7 confirmed the on-disk key is used directly and all three nodes
were reachable with an empty agent.

If it fails with `communication with agent failed` / `Permission denied
(publickey)` — which happened mid-session in session 9 — bypass the agent:

```
$ ssh -o IdentityAgent=none gabeduke@alphapi true && echo ok
```

## Prior-session context

`STATE.md` holds the running history (untracked — see `CLAUDE.md`).
`docs/tls-http01-outage.md` documents the session-3 TLS outage. Plan 03
originally argued that outage was probably caused by the bug it fixes; that is
**wrong** and plan 03's *Outcome* section explains why — the k3s serving cert
accumulates SANs and never drops them, so the dropped `alphapi` SAN kept being
served.
