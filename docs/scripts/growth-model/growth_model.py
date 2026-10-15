#!/usr/bin/env python3
"""Expected skill growth under the 2026-10-07 rule: 1 LP buys one improvement
attempt; d20 >= current level gives +1, so p(L) = (21 - L) / 20.

Prints a markdown table (levels gained per run, runs per level) and, if
matplotlib is installed and OUT.png is given, draws the expected level of one
skill over runs for 1, 2 and 3 LP per run, with the #64 tiered rule as a
best case (every run ends with a rest) for comparison.

Usage: python3 growth_model.py [OUT.png]

Assumptions: all of a run's LP go to the one skill being modelled (the
baseline's top skill got about 0.1-2 LP per run, the whole character about
1.0); LP per run is a whole number of attempts; levels are not capped.
Exact Markov-chain expectations, no sampling.
"""
import sys
from collections import defaultdict

LEVELS = [3, 5, 7, 12]
RATES = [1, 2, 3]


def p_new(level):
    """Chance that one attempt raises a skill at `level` (new rule)."""
    return max(0.0, min(1.0, (21 - level) / 20))


def after_attempts(dist, n):
    """Level distribution after n attempts under the new rule."""
    for _ in range(n):
        nxt = defaultdict(float)
        for lvl, pr in dist.items():
            p = p_new(lvl)
            nxt[lvl + 1] += pr * p
            nxt[lvl] += pr * (1 - p)
        dist = nxt
    return dist


def expected(dist):
    return sum(l * p for l, p in dist.items())


def levels_per_run(level, rate):
    """Expected levels gained in one run of `rate` attempts from `level`."""
    return expected(after_attempts({level: 1.0}, rate)) - level


def runs_to_next(level, rate):
    """Expected runs from `level` to `level + 1`: 20 / (21 - L) attempts / rate."""
    return (1 / p_new(level)) / rate


def runs_between(lo, hi, rate):
    return sum(runs_to_next(l, rate) for l in range(lo, hi))


# The #64 rule (baseline variant): an attempt needs the tier's LP (5/7/10/15),
# rolls d20 + tier modifier (Expert -3, Master -5) > level, sets LP to 0 on a
# hit and 1 on a miss. Best case: every run ends with a rest and has a failure.
def tier(level):
    if level <= 5:
        return 5, 0
    if level <= 10:
        return 7, 0
    if level <= 15:
        return 10, -3
    return 15, -5


def p_old(level):
    _, mod = tier(level)
    return sum(1 for r in range(1, 21) if r + mod > level) / 20


def old_rule_curve(start, rate, runs):
    dist = {(start, 0): 1.0}
    out = [start]
    for _ in range(runs):
        nxt = defaultdict(float)
        for (lvl, lp), pr in dist.items():
            lp += rate
            need, _ = tier(lvl)
            if lp >= need:
                p = p_old(lvl)
                nxt[(lvl + 1, 0)] += pr * p
                nxt[(lvl, 1)] += pr * (1 - p)
            else:
                nxt[(lvl, lp)] += pr
        dist = nxt
        out.append(sum(l * p for (l, _), p in dist.items()))
    return out


def new_rule_curve(start, rate, runs):
    dist = {start: 1.0}
    out = [start]
    for _ in range(runs):
        dist = after_attempts(dist, rate)
        out.append(expected(dist))
    return out


def table():
    lines = [
        "| Level L | p = (21 − L)/20 | Levels per run at 1 LP | at 2 LP | at 3 LP "
        "| Runs L → L+1 at 1 LP | at 2 LP | at 3 LP |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for l in LEVELS:
        gains = [f"{levels_per_run(l, r):.2f}" for r in RATES]
        runs = [f"{runs_to_next(l, r):.1f}" for r in RATES]
        lines.append(f"| {l} | {p_new(l):.2f} | " + " | ".join(gains) + " | " + " | ".join(runs) + " |")
    lines.append("")
    lines.append("| Span | Runs at 1 LP | at 2 LP | at 3 LP |")
    lines.append("|---|---|---|---|")
    for lo, hi in [(3, 5), (5, 7), (7, 12), (3, 12), (12, 16), (3, 20)]:
        lines.append(f"| {lo} → {hi} | " + " | ".join(f"{runs_between(lo, hi, r):.1f}" for r in RATES) + " |")
    lines.append("")
    lines.append("#64 rule, best case (every run rests, a failure each time), runs to the next level from L at 1 LP/run: "
                 + ", ".join(f"L{l}: {runs_old(l, 1):.1f}" for l in LEVELS))
    return "\n".join(lines)


def runs_old(level, rate):
    """Best-case expected runs to the next level under #64 (LP restart at 1 after a miss)."""
    need, _ = tier(level)
    p = p_old(level)
    if p == 0:
        return float("inf")
    first = need / rate
    retry = (need - 1) / rate
    return first + (1 / p - 1) * retry


def chart(out):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    runs = 40
    fig, ax = plt.subplots(figsize=(8, 4.5))
    for rate, col in zip(RATES, ["C0", "C1", "C2"]):
        ax.plot(range(runs + 1), new_rule_curve(3, rate, runs), "-", color=col, label=f"new rule, {rate} LP/run")
    ax.plot(range(runs + 1), old_rule_curve(3, 1, runs), "--", color="C7",
            label="#64 rule, 1 LP/run, best case (rest every run)")
    ax.set_xlabel("runs (sessions)")
    ax.set_ylabel("expected skill level")
    ax.set_title("One skill starting at level 3: 1 LP = one attempt, d20 ≥ level")
    ax.grid(alpha=.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(out, dpi=110)
    return out


if __name__ == "__main__":
    print(table())
    if len(sys.argv) > 1:
        try:
            print(chart(sys.argv[1]))
        except ImportError:
            print("(matplotlib not installed: no chart)")
