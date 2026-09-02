#!/usr/bin/env python3
# Aggregate an ims-ma3 census and state its error band.
#
# ☠️ THE GATE IS PER LEG, AND ITS SCALE IS THE LEG'S OWN SLEEP - NOT THE ALARM.
# The accumulator wraps at ACCUM_CNT = 255 at ~3.35-3.4 samples/s, so a sample
# whose cnt implies a window longer than the leg actually slept began BEFORE the
# sleep and carries the previous wake's awake current, always upward. On a leg
# that sleeps the full alarm the two scales coincide; on a leg that does not
# sleep - which is exactly what the expensive state does - they differ by 4x, and
# reading the gate as "3.35 x alarm" silently keeps 39 contaminated samples
# instead of 7 and pulls that leg from 91.0 mA down to 84.2 mA. Measured on the
# 2026-09-02 census while trying to reproduce its own published table.
#
# ☠️ AND AGGREGATE sum(accum)/sum(cnt), NOT a mean of per-sample means: each
# sample is an integral over a different number of ticks, so a plain mean weights
# a short window like a long one.
#
# usage: ma3-fit.py <capture-dir> [leg ...]
import sys, re, statistics as st, random, datetime as dt, pathlib

I_RAW_TO_UA = 152588 / 1000          # per the QG datasheet units, /1000 -> uA
SAMPLES_PER_S = 3.35                 # measured: 140 samples over 41 s of sleep
MIN_CNT = 20                         # ~6 s; below that the resume transient dominates

# ☠️ THE STATE COMES FROM WHAT THE LEG RECORDED, not from a flag typed later and
# not from the sleep distribution. The leg writes "IMS at start:" into its own
# log; that line IS the declaration, made by the run that set it. A flag can go
# stale against the capture it describes - which is the same failure as retyping a
# number - so the flag is only the fallback when the log says nothing.
def leg_state(d, leg):
    # ☠️ TWO FORMATS AND A SHARED FILE, and getting either wrong is silent. The
    # ladder writes one log for all three legs, headed "########## LEG A (IMS=on)";
    # the night writes one log per leg saying "IMS at start: voice=False ...". The
    # first version looked for "IMS at start" in a shared file and matched leg A's
    # line for every leg - and, missing the ladder's own wording, fell back to the
    # default and marked both expensive legs DISTURBED. A state read from the wrong
    # section is worse than no state, because it looks like an answer.
    try:
        txt = open(d / 'log.txt').read()
    except OSError:
        return None
    m = re.search(rf'^#* *#*#* *LEG {re.escape(leg)}\b.*\(IMS=(\w+)\)', txt, re.M)
    if m:                                    # the ladder's own declaration
        return 'cheap' if m.group(1) == 'off' else 'expensive'
    for line in txt.splitlines():            # a per-leg log from the night
        if 'IMS at start' not in line and 'IMS at leg start' not in line:
            continue
        vals = re.findall(r'=(\w+)', line)
        if vals:
            return 'cheap' if all(v in ('False', 'telephony') for v in vals) else 'expensive'
    return None


# ☠️☠️ ATTRIBUTION CHANGES THE LABEL, NEVER THE FATE. The login ledger tells the
# morning WHO woke the phone - the watchdog's poll at 19:52, a person at 03:14 -
# and that is worth having, because a source you can name is a source you can
# remove. It is NOT a licence to keep the leg. A disturbance that is understood
# perturbs the measurement exactly as much as one that is not, and the pull to
# keep a leg once its wake has a friendly explanation is the strongest one there
# is: the explanation feels like a correction. It is not one - nothing here
# subtracts the wake's cost from the samples. So the rule is mechanical: any
# non-allowlisted AP wake inside the leg window drops the leg from the aggregate.
# What attribution buys is the difference between dropping one leg and dropping
# the night, plus a named source to fix before the next run.
#
# ☠️ AND THE MIRROR FAILURE: "no ledger row, therefore clean". The ledger sees ssh
# and nothing else. An incoming call leaves no login and no unit; a unit start
# leaves no login; and a wake nobody has a name for leaves neither. So the four
# witnesses stay OR-ed - ledger, ring log, unit audit, and the statistical
# median-sleep detector - and a leg is clean only when ALL of them are silent.
# ☠️ Do not retire the statistical detector now that attribution exists: it is
# the only one of the four that is sensitive to a disturbance whose cause is not
# known in advance, which is the only kind that has ever surprised this project.
DROPPED = {}   # leg -> the witnesses that spoke; filled while printing, honoured below


def leg_audit(d, leg):
    """The leg's own audit lines. Returns the list of witnesses that spoke.

    ☠️ SCOPE THE READ TO THIS LEG'S SECTION - the SAME trap leg_state() was fixed
    for on this file, hours earlier, and the first version of this function walked
    straight into it: it read the shared ladder log and applied leg A's audit lines
    to every leg, convicting all three on one login. Demonstrated on this repo's own
    census before it could reach a night. The night writes leg{X}/log.txt, which is
    already scoped; the ladder writes one file with "LEG A (IMS=on)" headings, and
    those headings are the boundaries.
    """
    reasons = []
    txt = None
    try:
        txt = open(d / f'leg{leg}' / 'log.txt').read()   # per-leg file: already scoped
    except OSError:
        try:
            shared = open(d / 'log.txt').read()
        except OSError:
            return reasons
        heads = list(re.finditer(r'^#*\s*#*\s*LEG (\w+)\b', shared, re.M))
        if heads:
            for k, h in enumerate(heads):
                if h.group(1) == leg:
                    end = heads[k + 1].start() if k + 1 < len(heads) else len(shared)
                    txt = shared[h.start():end]
                    break
            if txt is None:
                return reasons          # this leg has no section: no audit, not a clean bill
        else:
            # ☠️ ONE UNHEADED FILE AND SEVERAL LEGS: there is no way to attribute an
            # audit line to a leg, so attributing it to ALL of them is the safe
            # direction. A false drop costs a leg; a missed one costs the answer.
            txt = shared
    for line in txt.splitlines():
        m = re.match(r'#\s*audit:\s*(ssh logins|incoming calls)[^=]*=\s*(\d+)', line)
        if m and int(m.group(2)) > 0:
            reasons.append(f'{m.group(1)} = {m.group(2)}')
        m = re.match(r'#\s*audit:\s*unexpected units started\s*=\s*(.+)', line)
        if m and m.group(1).strip() not in ('none', ''):
            reasons.append(f'unexpected units: {m.group(1).strip()}')
    return reasons


# ☠️ THE CONFIG CHECK AND THE RECONCILER READ THE SAME QMI GETTERS - and this
# project has already been bitten once by a setter and getter that did not
# correspond. If a getter reads the wrong switch, the configuration check lies
# green for ever and nothing notices. The independent layer is BEHAVIOUR: the
# modem's XO-shutdown duty is measured by the RPM, not reported by the modem, and
# the two states are far apart (cheap 4-7 %, expensive 31-52 %). Every leg records
# its MPSS window anyway, so the cross-check is free.
CHEAP_DUTY = (0.0, 12.0)
EXPENSIVE_DUTY = (25.0, 60.0)
TICK = 19200000.0

def leg_duty(d, leg, rows):
    # ☠️ USE THE ACCUMULATOR THE REST OF THIS REPO USES: `XO total duration` is the
    # summed sleep in RPM ticks, so awake duty = 1 - dSleep/dWall. The first
    # version of this function invented a formula out of the "Last XO shutdown
    # enter/exit" pair - two edge timestamps that say nothing about accumulated
    # time - and produced 100 % for a leg that was demonstrably asleep half the
    # window. A derived quantity nobody checked against a known case is a guess
    # with a percent sign on it.
    try:
        txt = open(d / f'mpss-{leg}.txt').read()
    except OSError:
        return None
    def acc(tag):
        m = re.search(rf'^{tag}\s+XO total duration: (\d+)', txt, re.M)
        return int(m.group(1)) if m else None
    b, a = acc('BEFORE'), acc('AFTER')
    if b is None or a is None or len(rows) < 2:
        return None
    wall = (rows[-1][0] - rows[0][0]).total_seconds()
    if wall <= 0:
        return None
    return max(0.0, min(100.0, 100.0 * (1 - (a - b) / TICK / wall)))


def load(d, leg):
    out = []
    for line in open(d / f'samples-{leg}.txt'):
        m = re.search(r't=(\S+ \S+) acc=0x([0-9a-f]+) cnt=0x([0-9a-f]+)', line)
        if not m:
            continue
        t = dt.datetime.strptime(m.group(1), '%Y-%m-%d %H:%M:%S')
        v = int(m.group(2), 16)
        if v >= 1 << 23:             # 24-bit signed, little endian
            v -= 1 << 24
        out.append((t, v, int(m.group(3), 16)))
    return out

def ma(kept):
    return sum(v for v, c in kept) * I_RAW_TO_UA / sum(c for v, c in kept) / 1000

# ☠️ TWO WRONG ANSWERS BEFORE THIS ONE, AND THE SECOND WAS A REVIEWER'S.
#
# First a bootstrap at every n. Resampling 7 values estimates its own tail, so it
# printed +-8.4 mA off 7 samples and looked exactly as authoritative as the +-1.1
# off 22.
#
# Then, on review, a t interval below n=15. That was worse, and the same reviewer
# retracted it a round later: the POINT estimate is the cnt-weighted sum/sum, in
# which a short noisy window carries little weight, while a t interval runs on the
# UNWEIGHTED per-window means, where those same windows dominate the spread. The
# two do not describe the same quantity - which is how leg A' went from +-8.4 to
# +-43.3 without any new data.
#
# The estimator that matches the point estimate is the weighted variance of the
# weighted mean: Var(mu) = sum(w_i^2 (x_i - mu)^2) / (sum w_i)^2, with w = cnt.
# It neither flatters short windows nor lets them dominate, and it needs no
# resampling at any n.
T975 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365,
        8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179, 13: 2.160,
        14: 2.145, 15: 2.131, 20: 2.086, 21: 2.080, 30: 2.042}

def t975(df):
    if df in T975:
        return T975[df]
    return next(v for k, v in sorted(T975.items()) if k >= df) if df < 30 else 1.96

def leg_stats(rows, state='cheap', boots=0):
    gaps = [(rows[i + 1][0] - rows[i][0]).total_seconds() for i in range(len(rows) - 1)]
    med = st.median(gaps)
    # ☠️ THE GATE'S SCALE MUST BE DECLARED, NOT MEASURED - the same self-reference
    # that was taken out of the disturbance test. On a leg that was woken, the
    # median shrinks, the gate slides down with it, and it becomes LENIENT exactly
    # on the disturbed windows: that is how the rehearsal's 45.1 mA was produced
    # from a leg woken every 9 s. A cheap leg is SUPPOSED to sleep its alarm, so
    # the alarm is the scale. An expensive leg has no such expectation, so there
    # the measured median is all there is - and nothing is being protected.
    thr = SAMPLES_PER_S * (ALARM if (ALARM and state == 'cheap') else med)
    # ☠️ THE GATE NEEDS A FLOOR AS WELL AS A CEILING, and it took an outlier
    # detector to notice. Leg A' held a window with cnt = 1 - a single accumulator
    # tick, i.e. an instantaneous reading with no averaging at all - which came out
    # as 303.7 mA and, by itself, produced most of that leg's spread. Below roughly
    # six seconds the window is shorter than the resume transient sitting inside
    # it, so it measures the wake rather than the sleep. Dropping those is not
    # trimming inconvenient data: cnt is how many samples the hardware averaged,
    # and a one-sample average is not the quantity this script claims to report.
    kept = [(v, c) for _, v, c in rows if MIN_CNT <= c < thr]
    if not kept:
        return None
    point = ma(kept)
    n = len(kept)
    per = [v * I_RAW_TO_UA / c / 1000 for v, c in kept]
    if n < 2:
        return dict(med=med, thr=thr, kept=n, n=len(rows), ma=point,
                    lo=point, hi=point, how='n=1, no spread', out=[])
    w = [c for _, c in kept]
    sw = sum(w)
    var = sum((wi ** 2) * ((xi - point) ** 2) for wi, xi in zip(w, per)) / (sw ** 2)
    half = t975(n - 1) * var ** 0.5
    # ☠️ NAME THE OUTLIERS INSTEAD OF LETTING THEM BE A NUMBER. A leg whose spread
    # comes from one or two windows is not a noisy leg, it is a leg with something
    # in it that needs looking at - a window that caught the screen, a boot
    # remnant, a wake that never slept. The band alone hides that.
    med_x = st.median(per)
    out = [(round(x, 1), c) for x, (_, c) in zip(per, kept) if abs(x - med_x) > 3 * (st.median(
        [abs(y - med_x) for y in per]) or 1)]
    return dict(med=med, thr=thr, kept=n, n=len(rows), ma=point,
                lo=point - half, hi=point + half,
                how=f'weighted, df={n - 1}', out=out)


# ☠️ A LEG THAT DID NOT SLEEP ITS ALARM WAS DISTURBED, AND THE GATE HIDES IT.
# The gate scales with the leg's OWN median sleep, which is right - but it means a
# leg woken every 9 s against a 90 s alarm still produces a number, computed over
# a threshold of 30 and one surviving sample, and nothing in the output says the
# leg was interfered with. Measured: a rehearsal leg came back at 9 s median
# because this session ssh'd and pinged the phone in the middle of it to answer a
# question - the same interference this project had warned the owner about that
# morning. An ssh login is an AP wake. So the fit says it out loud.
def disturbed(med, alarm, expensive=False):
    # ☠️ THE THRESHOLD IS ONLY MEANINGFUL ON A LEG THAT IS SUPPOSED TO SLEEP. An
    # expensive leg (IMS on) wakes every 16-18 s against a 90 s alarm BY ITS OWN
    # NATURE - a ratio of ~0.2 - so a single threshold would mark every such leg
    # disturbed and would then say nothing about one that really was. Derivation of
    # the 0.6 for a cheap leg: undisturbed the ratio is ~0.97 (the alarm minus a
    # 2-3 s resume), and the MEDIAN only falls below 0.6 if half the sleeps are
    # short, which needs ln2/54 = 46 AP wakes an hour - not "the modem woke a few
    # times". On an expensive leg the only usable witness is the login/unit audit
    # the leg itself keeps.
    if not alarm:
        return False
    return med < (0.05 if expensive else 0.6) * alarm

# ☠️ THE TABLE IN THE REPORT IS GENERATED BY THIS, NOT RETYPED. Copying numbers
# by hand is how a published table drifts from the data it claims to summarise -
# and this file exists because reproducing one such table took a sixth review
# round to explain. `--md` prints the markdown rows; paste those, nothing else.
MD = '--md' in sys.argv
# --alarm <s> lets the fit compare the sleep it sees with the sleep that was asked for
ALARM = 0
STATE = 'expensive' if '--state' in sys.argv and sys.argv[sys.argv.index('--state') + 1] == 'expensive' else 'cheap'
if '--alarm' in sys.argv:
    ALARM = float(sys.argv[sys.argv.index('--alarm') + 1])
argv = [a for a in sys.argv if a != '--md']
for opt in ('--alarm', '--state'):
    if opt in argv:
        i = argv.index(opt); del argv[i:i + 2]
d = pathlib.Path(argv[1])
d = d / 'raw' if (d / 'raw').is_dir() else d
legs = argv[2:] or [p.name[8:-4] for p in sorted(d.glob('samples-*.txt'))]
if MD:
    print('| leg | slept | kept | **current** | 95 % CI (within-leg only) |')
    print('|---|---:|---:|---:|---|')
else:
    print(f"{'leg':<4} {'sleep':>7} {'gate':>7} {'kept':>8} {'current':>10}   95% CI (within-leg only)"
          f"   [gate: {MIN_CNT} <= cnt < 3.35 x "
          f"{'the ALARM on a cheap leg, the measured median on an expensive one' if ALARM else 'the measured median'}]")
for leg in legs:
    r = leg_stats(load(d, leg), leg_state(d, leg) or STATE)
    if not r:
        print(f'{leg:<4} no sample survives the gate')
        continue
    if MD:
        print(f"| {leg} | {r['med']:.0f} s | {r['kept']}/{r['n']} | {r['ma']:.1f} mA | "
              f"±{(r['hi']-r['lo'])/2:.1f} ({r['how']}) |"
              + (f"  <!-- outliers: {r['out']} -->" if r['out'] else ''))
        continue
    print(f"{leg:<4} {r['med']:>6.0f}s {r['thr']:>7.0f} {r['kept']:>4}/{r['n']:<3} "
          f"{r['ma']:>8.1f} mA   [{r['lo']:.1f}, {r['hi']:.1f}]  +-{(r['hi']-r['lo'])/2:.1f}  ({r['how']})")
    # ☠️ NEVER INFER THE STATE FROM THE QUANTITY THAT TESTS IT. The first attempt
    # decided "this is an expensive leg" from the sleep ratio - and an expensive
    # leg and a DISTURBED CHEAP leg look identical by that measure, so the very
    # case the detector exists for (a cheap leg woken by an ssh, ratio 0.1) was
    # excused as normal. Measured on this repo's own disturbed leg, immediately.
    # The state is declared with --state, and defaults to cheap: the failure mode
    # of the default must be a false alarm, never a missed one.
    st_leg = leg_state(d, leg) or STATE
    expensive = st_leg == 'expensive'
    witnesses = leg_audit(d, leg)
    if ALARM and disturbed(r['med'], ALARM, expensive):
        witnesses.append(f"median sleep {r['med']:.0f} s against a {ALARM:.0f} s alarm")
    if witnesses:
        DROPPED[leg] = witnesses
        print(f"       ☠️☠️ THIS LEG IS DROPPED FROM THE AGGREGATE: {'; '.join(witnesses)}.")
        print(f"       Something woke the AP. The number above is not the sleeping floor of")
        print(f"       anything, and no attribution of the wake changes that - naming the")
        print(f"       source buys the next run, not this leg.")
    elif ALARM and expensive:
        print(f"       (median sleep {r['med']:.0f} s against a {ALARM:.0f} s alarm - expected for "
              f"a leg that holds a connection; the sleep test cannot see interference here, "
              f"read the leg's own login/unit audit instead)")
    duty = leg_duty(d, leg, load(d, leg))
    if duty is not None:
        band = EXPENSIVE_DUTY if (leg_state(d, leg) or STATE) == 'expensive' else CHEAP_DUTY
        if not band[0] <= duty <= band[1]:
            print(f"       ☠️☠️ THE BEHAVIOUR DISAGREES WITH THE DECLARED STATE: modem duty "
                  f"{duty:.1f} % against the {band[0]:.0f}-{band[1]:.0f} % expected for a "
                  f"'{(leg_state(d, leg) or STATE)}' leg. The configuration check and the "
                  f"reconciler share the QMI getters; this does not. Believe this one.")
    if r['out']:
        print(f"       ☠️ look at these windows before calling this statistics: "
              f"{', '.join(f'{x} mA (cnt {c})' for x, c in r['out'])}")
if MD:
    sys.exit(0)
# ☠️ THE GAP IS COMPUTED HERE TOO, because the last time it was typed into prose
# it went stale the moment the estimator changed: the report said +-12.3 for weeks
# after the band it was built from had become +-10.4. A number a human retypes is
# a number that drifts from its own fit.
res = {leg: leg_stats(load(d, leg), leg_state(d, leg) or STATE) for leg in legs}
# ☠️ THE DROP HAS TO BITE HERE, not only in the printout above. A warning beside a
# number that is then used anyway is how the rehearsal's 45.1 mA got published.
for leg in list(res):
    if leg in DROPPED:
        res[leg] = None
cheap = min((r for r in res.values() if r), key=lambda r: r['ma'], default=None)
if cheap:
    for leg, r in res.items():
        if not r or r is cheap:
            continue
        gap = r['ma'] - cheap['ma']
        half = ((r['hi'] - r['lo']) ** 2 / 4 + (cheap['hi'] - cheap['lo']) ** 2 / 4) ** 0.5
        print(f"gap {leg} - cheapest: {gap:.1f} mA  +-{half:.1f}  (quadrature of the two within-leg bands)")
if DROPPED:
    print()
    print('☠️ LEGS DROPPED FROM THE AGGREGATE (attribution does not restore them):')
    for leg, why in DROPPED.items():
        print(f'   {leg}: {"; ".join(why)}')
    print('   A dropped leg is not a failed night. If a comparison still has one clean')
    print('   leg per state, it stands on fewer legs and says so; if it does not, the')
    print('   night answered nothing and the honest report is that, not the mean of')
    print('   whatever survived.')
print()
print('☠️ THE CI IS WITHIN-LEG ONLY - the sampling noise of one leg of one boot.')
print('   It says nothing about the PMI632 offset the whole project shares, and')
print('   nothing about the DOMINANT unknown, which is boot-to-boot variation: no')
print('   single leg can see that, however many windows it holds. Label every')
print('   number from here "+-X (within-leg; boot-to-boot unknown)", and once')
print('   several boots exist take the boot-to-boot spread from the SPREAD OF THE')
print('   LEG MEANS - never from the pooled windows, which would hide it.')
