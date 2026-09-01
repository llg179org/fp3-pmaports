# The modem's IMS state is NOT readable with the tools on this device — the test came back "unreadable", not "confirmed"

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely, who reviewed the measurement it rests on.

2026-09-01 20:15, before the overnight decay window was opened (these reads are
interactions with the modem, so they had to happen first or not at all).

## Why it was asked

The leading explanation for the two modem regimes — a cheap ~5 % XO duty and an
expensive ~35 % one — is that something inside the modem is **retrying a
procedure with exponential backoff**, and the reviewer's first candidate is the
modem's own embedded **IMS client**, retrying registration against a network our
stack never provisions it for. That would explain the bistability, the growth of
the quiet stretches when the phone is left alone, and why every reset lands in
the expensive state.

If the IMS client's registration status were readable, the hypothesis would be
one command away from a verdict.

## What was measured

| read | result |
|---|---|
| `qmicli --imsa-get-ims-registration-status` | `QMI protocol error (70): 'InvalidOperation'` |
| `qmicli --imsa-get-ims-services-status` | `QMI protocol error (70): 'InvalidOperation'` |
| `qmicli --ims-get-ims-services-enabled-setting` | `QMI protocol error (70): 'InvalidOperation'` |
| `qmicli --imsp-get-enabler-state` | `QMI protocol error (3): 'Internal'` — the client cannot even be created |
| `qmicli --imsa-noop`, `--ims-noop` | **succeed** (silent) |
| `qrtr-lookup` | IMS QMI Priv (77), **IMS application (33)**, IMS settings (18) all present |

So the services are **registered on the qrtr bus and will allocate a client**,
and then refuse every state query.

## The bind, and why it cannot be done from `qmicli` here

Both services expose a `--imsa-bind` / `--ims-bind` action, documented "use with
`--client-no-release-cid`". The obvious next step fails on the transport:

```
$ qmicli -d qrtr://0 --imsa-bind=0 --client-no-release-cid   → "IMSA bind successful", CID 1
$ qmicli -d qrtr://0 --client-cid=1 --imsa-get-ims-registration-status
error: operation failed: Unknown client 1 for service imsa
```

☠️ **A qrtr client ID does not survive the process that allocated it.** On a
`cdc-wdm` device the CID is a property of the device node and a second `qmicli`
can adopt it; over `qrtr://` it belongs to the socket, which closes with the
process. And `qmicli` refuses to do both in one process — `error: too many IMSA
actions requested`.

Binding and reading in one process therefore needs a program that is not
`qmicli` (a few lines against libqmi, or a `qmi-firmware-update`-style helper).
That was **not** written tonight: the overnight window was the higher-value use
of the remaining time, and it had to start before midnight to run its full
length.

## What this does and does not license

**Licensed:** the IMS services exist and answer a noop, so the modem's IMS stack
is loaded — the hypothesis is not dead on "there is no IMS client here".

**Not licensed:** anything about whether it is registering, retrying, or idle.
`InvalidOperation` on an unbound client is the expected answer for *any* state,
so it distinguishes nothing. In particular it must **not** be written up as
"IMS is unprovisioned, consistent with a retry loop" — that reads a verdict out
of a refusal to answer.

## Next, if this is worth another hour

A ~30-line libqmi program that opens one qrtr client, sends IMSA Bind, then IMSA
Get Registration Status on the same client. That is the only path to the reading;
everything shipped on the device has now been tried.
