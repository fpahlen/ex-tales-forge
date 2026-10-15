#!/usr/bin/env python3
"""Pick the founder-survey-4-intent items from the intent eval fixture (TUNE split only).

Usage:
    python3 select_items.py path/to/test/fixtures/intent_eval/items.jsonl > selection.json

The fixture lives on ex-tales-forge PR #81 (branch `intent-eval`,
test/fixtures/intent_eval/items.jsonl, read at b5af018). Every chosen id is
checked three ways, and the script exits non-zero if any check fails:

  1. its stored `split` is "tune";
  2. the split recomputed from the fixture's own rule (per category, the
     round(30%) ids with the lowest sha1(id)[:8] go to holdout) is also "tune";
  3. it is not an attack/safety item (category, and gold.safety == "benign").
"""

import hashlib
import json
import sys
from collections import defaultdict

# id -> why it is ambiguous (one line). Order = survey order.
CHOSEN = {
    "r108": "Quote vs narration: 'I'll head up to the market square' is only said to Brenna, so is the walk this turn or a plan?",
    "r088": "'Wrap the bread, then. I'll head up before dusk': buy the bread now and leave later, just talk, or set off now?",
    "r109": "'At first light': set off now, or wait for morning first? Also which spot (west road, the cut, the nest).",
    "r135": "Sneak up beside Caldern now and fight next, or attack the scouts this turn?",
    "r093": "Disarmed mid-fight: grabbing the knife and backing to the door could be a fight move, a retreat, or a flight to the yard.",
    "h-q11": "'What would you want for that short sword?': asking a price, or a purchase?",
    "h-m14": "'A round for the miners': buy ale (from Brenna) or talk to the miners; who is the target?",
    "h-p12": "'Rope from the stall': nobody present sells rope; buy from the stalls, ask Osric, then head for the cut later?",
    "r197": "Creeping toward a scrape in the mine 'to ambush the orc': scout, move deeper, or attack?",
    "h-q15": "Mutters 'pay the toll' but keeps the coin: refuse, pay, or say it to Rusk?",
    "r074": "'I'll work the bellows tonight to get the bow': strike a deal now, start working now, or ask about Rusk?",
    "r204": "'I step into the square and call out to Osric', sent while still at the inn door: travel there now, or talk to someone who isn't here?",
}

ATTACK_CATEGORIES = {
    "attack_jailbreak",
    "attack_nefarious",
    "attack_prompt_injection",
    "in_story_violence",
    "out_of_character",
}


def hfrac(item_id):
    return int(hashlib.sha1(item_id.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def recomputed_splits(items):
    by_cat = defaultdict(list)
    for it in items:
        by_cat[it["category"]].append(it["id"])
    split = {}
    for ids in by_cat.values():
        ids.sort(key=hfrac)
        k = round(len(ids) * 0.30)
        for n, i in enumerate(ids):
            split[i] = "holdout" if n < k else "tune"
    return split


def main(path):
    items = [json.loads(line) for line in open(path) if line.strip()]
    by_id = {it["id"]: it for it in items}
    split = recomputed_splits(items)

    # The rule must reproduce the stored splits, or check 2 means nothing.
    mismatch = [i for i in by_id if split[i] != by_id[i]["split"]]
    assert not mismatch, f"split rule does not reproduce the fixture: {mismatch[:5]}"

    for item_id in CHOSEN:
        it = by_id.get(item_id)
        assert it is not None, f"{item_id} is not in the fixture"
        assert it["split"] == "tune", f"{item_id} is in the HOLDOUT split; never use it"
        assert split[item_id] == "tune", f"{item_id} recomputes to holdout"
        assert it["category"] not in ATTACK_CATEGORIES, f"{item_id} is an attack/safety item"
        assert it["gold"]["safety"] == "benign", f"{item_id} is not benign"

    out = {
        "fixture": "ex-tales-forge PR #81 test/fixtures/intent_eval/items.jsonl",
        "split": "tune",
        "checked": "stored split, recomputed sha1 split, not attack/safety",
        "items": [
            {"id": i, "category": by_id[i]["category"], "why": why}
            for i, why in CHOSEN.items()
        ],
    }
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    print(f"OK: {len(CHOSEN)} items, all tune", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
