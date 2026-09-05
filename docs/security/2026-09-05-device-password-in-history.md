# The device password was committed, and the history rewrite did not fully undo it

2026-09-05. Recorded because the remediation is incomplete by nature, and the
part that is still outstanding is not something a commit can do.

> ⚠️ **AI-generated.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely.

## What was exposed

The pmOS user's password — the one `fp3-ssh` feeds to `sudo -S`, the same
password on both slots — was committed as a literal in **14 places across 13
files**: documentation showing example ssh commands, and four tools using it as
a `PW=${FP3_PW:-<secret>}` default. It was present in **487 blobs** across the
repository's history.

**This repository is public.** `curl` against `github.com/llg179org/fp3-pmaports`
returns 200 without authentication.

It was found by grepping for it by hand, not by any check. `tests/no-identifiers.sh`
had run before every capture commit for days and never looked for it.

## What was done

1. **Working tree.** Documentation now says `<pw>`. The four `:-` defaults are
   gone — a default is a baked-in secret with a friendly face, so the tools now
   refuse with `${FP3_PW:?…}`. Two sites sat inside single quotes, where an
   expansion does not happen, and use `'echo '"$FP3_PW"' | …'`; that idiom was
   *proven* to expand (`FP3_PW=SENTINEL` → `echo SENTINEL | sudo -S x`) rather
   than assumed, and every modified script passes `sh -n`.
2. **History.** Rewritten with `git-filter-repo --blob-callback`, replacing the
   literal in every blob. ☠️ `--replace-text` was deliberately not used: it skips
   binary blobs, the same blind spot grep has. Here 487 blobs were text and 0
   binary, so it would have sufficed — but that was measured afterwards, not
   assumed beforehand.
3. **Verified, with a negative control.** The new history: 0 of 4856 blobs carry
   it. The pre-rewrite bundle, scanned the same way: 7268 hits. A clean result
   from a scanner that has not been shown finding anything proves nothing.
4. **Fresh clone from GitHub**: 0 hits, 1318 commits.
5. **The guard now looks for it.** `tests/no-identifiers.sh` greps for `$FP3_PW`
   when the environment has it, printing any hit with the secret masked. It is
   skipped when `FP3_PW` is unset — stated in the file rather than left to be
   discovered, because that silence is how this survived.

## ☠️ What is NOT fixed, and cannot be by us

**GitHub still serves the pre-rewrite commits by SHA.** Measured after the
force-push:

```
https://github.com/llg179org/fp3-pmaports/archive/<a pre-rewrite sha>.tar.gz   -> 200
https://github.com/llg179org/fp3-pmaports/archive/deadbeef…deadbeef.tar.gz     -> 404
```

The object is unreachable from every ref and still downloadable by anyone who
knows or guesses the hash, until GitHub garbage-collects it. Only GitHub Support
can force that.

And a rewrite reaches nobody who already cloned, forked, or scraped the
repository while the secret was in it.

**So the only real remediation is to change the password on the device.** Until
that is done, this is a live credential that has been published, not a
historical mistake that has been cleaned up. Everything above only stops it
being published *again*.

## The lesson worth keeping

The check that should have caught this existed, ran constantly, and reported
clean — because nobody had told it what a password looks like. Two days earlier
the same check was extended for a phone number after the same class of miss.
**A guard only covers what it was told about, and "it says clean" is a statement
about its patterns, not about the tree.**
