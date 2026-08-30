# Draft reply to the AW8898 v2 posting — SYSST must be volatile

> ⚠️ **AI-generated draft.** Written by Claude (Opus 5) under the direction of
> Lajosházi, László Gergely. **Not sent.** Sending is a separate, human decision;
> nothing here goes to a public list without review.

## Why a reply and not a patch in our series

The driver is **not ours and not in mainline**: it reaches our base as a
FROMLIST commit of Luca Weiss's v2. Carrying our fix inside the FP3 audio
submission would make our series depend on somebody else's unmerged one, in the
wrong direction. The correct move is to report it against the posting.

## Verified before drafting (2026-08-30)

| claim | how it was checked |
|---|---|
| the series is still unmerged | thread's last message is Mark Brown, **2025-07-07**; no "Applied to", no Acked-by, no v3 |
| the posted v2 sets `REGCACHE_MAPLE` | `git show <FROMLIST commit>:sound/soc/codecs/snd-soc-aw8898.c` — `.cache_type = REGCACHE_MAPLE` |
| the posted v2 declares no `volatile_reg` | same file, `grep -c volatile_reg` → **0** |

- Series (v2): `20250705-aw8898-v2-0-9c3adb1fc1a2@lucaweiss.eu`
- Driver patch (2/3): `20250705-aw8898-v2-2-9c3adb1fc1a2@lucaweiss.eu`
- Thread as fetched: <https://lore-kernel.gnuweeb.org/linux-sound/20250705-aw8898-v2-0-9c3adb1fc1a2@lucaweiss.eu/T/>

☠️ Confirm the status again immediately before sending — this table is dated, and
a v3 may have landed since. **Re-confirmed 2026-08-30**: still not in mainline,
still no v3 (details in "Before sending" below).

## The draft

> Subject: Re: [PATCH v2 2/3] ASoC: codecs: Add Awinic AW8898 amplifier driver
>
> Hi Luca,
>
> On the Fairphone 3 (sdm632, mainline) this driver's `.prepare` PLL wait never
> observes the lock, and the cause is in `aw8898_regmap`:
>
>     .cache_type = REGCACHE_MAPLE,
>
> with no `.volatile_reg`. Every register in the map is therefore cacheable,
> `AW8898_SYSST` included — and `SYSST` is what `.prepare` polls with
> `regmap_read_poll_timeout()` to wait for the PLL. The first read populates the
> cache and every later one is answered from it, so the loop spins on a single
> sample and times out whether or not the PLL locked in the meantime.
>
> What we measured, rather than what we inferred, is an A/B on the error code
> itself. With the driver as posted, `.prepare` logs
>
>     aw8898 4-0034: iis clock not detected (-110), playing anyway
>
> `-110` is `-ETIMEDOUT`: the poll ran its full timeout without the condition
> ever becoming true, which is what a loop spinning on one cached sample looks
> like. With `SYSST` marked volatile and nothing else changed, the same line on
> the same board reads
>
>     aw8898 4-0034: iis clock not detected (-5), playing anyway
>
> `-5` is `-EIO`, i.e. `regmap_read_poll_timeout()` now performs a real bus read
> on every iteration and that read fails. The timing says the same thing
> independently: the retries are then tens of milliseconds apart across ~0.6 s,
> where the cached version had spent the whole one-second timeout.
>
> So on our board the fix does not make the amplifier work — it turns a wrong
> answer into an honest one, and reveals a separate problem one layer down (the
> chip stops answering on I2C at the point DAPM powers the widget). That part is
> ours to chase, and I mention it only to be clear about what the change is and
> is not evidence for: it shows the poll became real, not that the PLL locks.
>
> Marking the status register volatile fixes it here:
>
>     +static bool aw8898_volatile_reg(struct device *dev, unsigned int reg)
>     +{
>     +	switch (reg) {
>     +	case AW8898_SYSST:
>     +		return true;
>     +	default:
>     +		return false;
>     +	}
>     +}
>     +
>      static const struct regmap_config aw8898_regmap = {
>      	.reg_bits = 8,
>      	.val_bits = 16,
>      	.max_register = AW8898_MAX_REGISTER,
>      	.cache_type = REGCACHE_MAPLE,
>     +	.volatile_reg = aw8898_volatile_reg,
>      };
>
> It is worth checking the rest of the map for the same class of register while
> you are there — anything the hardware updates on its own has the same problem,
> and the failure is silent by construction.
>
> Assisted-by: Claude:claude-opus-5
>
> Regards,
> László

## ☠️ Before sending

1. **Re-check the thread for a v3 or an "Applied to."** Verified 2026-08-30:
   `snd-soc-aw8898.c` is **not** in mainline (`raw.githubusercontent.com` → 404,
   absent from `sound/soc/codecs/Makefile`), and patchwork lists v1 (2025-04-06)
   and v2 (2025-07-05) with every patch in state `new` — **no v3**. Re-run the
   check if this sits for more than a few days.
2. ~~Fill in the cache-bypassed read that shows the lock bit set.~~ **Resolved by
   removing it, 2026-08-30.** That measurement does not exist and our own record
   says the opposite happened: when the poll became real it returned `-EIO`, and
   the conclusion of 2026-08-16 was that the amplifier does not answer on I2C at
   all — the PLL-lock question was never answered positively. The draft now
   reports the `-110` → `-5` A/B, which is measured, and says plainly what it is
   and is not evidence for. ☠️ **This is the class of error to keep watching for
   in an outgoing draft: a plausible positive observation, written from the
   shape of the argument rather than from a capture.**
3. `Assisted-by:` and **no** `Signed-off-by` from the assistant — this is
   upstream-bound. (Judgement call: that trailer is a *commit* convention and
   this is a plain report, so a sentence would read more naturally. Keeping it
   costs nothing and matches the disclosure practice used everywhere else here.)
