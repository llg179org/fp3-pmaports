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
a v3 may have landed since.

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
> What we measured, rather than what we inferred: on this board the poll times
> out and the driver takes the amplifier into PDN, which shows up as a silent
> speaker; writes to the amp's mixer controls then return -EIO on the control
> bus while playback is running. The distinguishing evidence for the cache
> (rather than a genuinely unlocking PLL) is that a *real* bus read of `SYSST`,
> taken with the cache bypassed, shows the lock bit set at a point where the
> driver's own poll is still reading its first sample back.
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

1. Re-check the thread for a v3 or an "Applied to" (see the dated table above).
2. Fill in the one sentence that is currently a summary, not a citation: the
   exact cache-bypassed read that shows the lock bit set. **If that measurement
   cannot be produced from a capture, cut the sentence** — the rest of the report
   stands on the code and the timeout alone, and an unsupported measurement claim
   in a first message to a maintainer is worse than a shorter message.
3. `Assisted-by:` and **no** `Signed-off-by` from the assistant — this is
   upstream-bound.
