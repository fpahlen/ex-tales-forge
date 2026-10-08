#!/usr/bin/env python3
"""Build docs/founder-survey-4-intent.json and mapping.json from the fixture.

Usage (from tales-forge-docs/docs/scripts/survey-intent):

    python3 select_items.py <items.jsonl> > selection.json
    # jev_readings.exs (see its header) -> jev-readings-2026-10-08.json
    python3 build_survey.py <items.jsonl>

Checks, each fatal:
  * every item is in the TUNE split (stored and recomputed; select_items.py);
  * every choice's labels are backed field by field by the item's gold, its
    `acceptable_*` values, or Jev's reading for that field (argmax or a
    runner-up with p >= 0.05) in jev-readings-*.json;
  * exactly one choice carries the primary gold labels (never marked in the
    survey; only mapping.json records it);
  * no two choices share labels or wording (dedupe);
  * no internal ids or label words leak into what founders read.

Choices are shuffled per item with a seed from sha1(item id), so a rebuild
gives the same order. "Unclear, the game should ask the player" and
"Something else" always come last.
"""

import hashlib
import json
import os
import random
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from items_spec import ITEMS  # noqa: E402
from select_items import CHOSEN, recomputed_splits  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.normpath(os.path.join(HERE, "..", ".."))
SURVEY_ID = "founder-survey-4-intent"
SURVEY_PATH = os.path.join(DOCS, SURVEY_ID + ".json")
MAPPING_PATH = os.path.join(HERE, "mapping.json")
JEV_PATH = os.path.join(HERE, "jev-readings-2026-10-08.json")
JEV_MIN_P = 0.05

UNCLEAR = "Unclear, the game should ask the player"
SOMETHING_ELSE = "Something else (tell us below)"
LABEL_KEYS = ["reading", "action", "target", "when", "later", "later_target"]
FIELDS = ["action", "target", "later", "later_target"]

SPECIAL_LABELS = {
    UNCLEAR: dict(reading="should_ask", action=None, target=None, when=None, later=None, later_target=None),
    SOMETHING_ELSE: dict(reading="something_else", action=None, target=None, when=None, later=None, later_target=None),
}

INTRO = (
    "Hi! When a player types something vague, the game has to guess what they mean, "
    "and a wrong guess plays out wrong: a purchase nobody asked for, a fight that "
    "should have been a sneak, a trip that was only a plan.\n\n"
    "Here are 12 real and made-up player lines where we think more than one reading "
    "is fair. For each one, read the scene, then pick what **you** think the player "
    "means. This is not a test; we want your gut, as a player. "
    "If it could honestly go either way, pick **\"Unclear, the game should ask the "
    "player\"**: that is a useful answer, it tells us when the game should check "
    "before acting. About 10 minutes.\n\n"
    "Answers save as you go, and you can change them until the survey closes."
)


def norm(v):
    return None if v in (None, "none") else v


def gold_tuple(g):
    return (g["action"], g["target"], g["later"], g["later_target"])


def backing(item, jev, labels):
    """Where each field value comes from; raises if a field is unbacked."""
    g = item["gold"]
    p = jev["probabilities"]
    jev_vals = {f: {norm(k) for k, v in p[f].items() if v >= JEV_MIN_P} for f in FIELDS}
    for f in FIELDS:
        jev_vals[f].add(norm(jev["reading"][f]))
    acc = {
        "action": set(g["acceptable_actions"]) | {g["action"]},
        "target": set(g["acceptable_targets"]) | {g["target"]},
    }
    laters = {(lt["type"], lt["target"]) for lt in g["acceptable_laters"]} | {(g["later"], g["later_target"])}
    out = {}
    for f in FIELDS:
        v = labels[f]
        src = []
        if v == g[f]:
            src.append("gold")
        if f in acc and v in acc[f]:
            src.append("acceptable")
        if f == "later" and any(t == v for t, _ in laters):
            src.append("acceptable")
        if f == "later_target" and (labels["later"], v) in laters:
            src.append("acceptable")
        if v in jev_vals[f]:
            src.append("jev")
        if not src:
            raise SystemExit(f"{item['id']}: {f}={v!r} is not gold, acceptable or a Jev reading")
        out[f] = sorted(set(src))
    return out


def scene_markdown(scene):
    lines = [
        f"**Where:** {scene['where']}.  ",
        f"**Who's here:** {scene['here']}.  ",
        f"**The player is:** {scene['playing']}.",
    ]
    if scene["turns"]:
        lines += ["", "**The player's last turns:**", ""]
        lines += [f"- {t}" for t in scene["turns"]]
    lines += ["", "**The game just said:**", "", "> " + scene["game"]]
    return "\n".join(lines)


def main(fixture_path):
    items = {json.loads(l)["id"]: json.loads(l) for l in open(fixture_path) if l.strip()}
    split = recomputed_splits(list(items.values()))
    jev = {r["id"]: r for r in json.load(open(JEV_PATH))["readings"]}
    assert list(ITEMS) == list(CHOSEN), "items_spec.py and select_items.py disagree"

    # Every id (store, worlds) that must never show up in founder-facing text.
    leak_words = set()
    for r in jev.values():
        leak_words |= {c["id"] for c in r["candidates"] if "_" in c["id"]}
    leak_words |= {"gold label", "acceptable", "holdout", "tune split"}

    sections, mapping = [], []
    for n, (item_id, spec) in enumerate(ITEMS.items(), start=1):
        item = items[item_id]
        assert item["split"] == "tune" and split[item_id] == "tune", f"{item_id} is not tune"

        choices, seen_labels, seen_texts, gold_count = [], set(), set(), 0
        for text, labels in spec["choices"]:
            key = tuple(labels[f] for f in FIELDS)
            assert key not in seen_labels, f"{item_id}: duplicate labels {key}"
            assert text not in seen_texts, f"{item_id}: duplicate wording"
            seen_labels.add(key)
            seen_texts.add(text)
            is_gold = key == gold_tuple(item["gold"])
            gold_count += is_gold
            full = dict(reading="choice", when="now, then later" if labels["later"] else "now", **labels)
            choices.append({
                "option": text,
                "labels": {k: full[k] for k in LABEL_KEYS},
                "backed_by": backing(item, jev[item_id], labels),
                "is_gold_now": is_gold,
            })
        assert 3 <= len(choices) <= 4, f"{item_id}: needs 3-4 choices"
        assert gold_count == 1, f"{item_id}: exactly one choice must carry the current gold"

        rng = random.Random(int(hashlib.sha1(item_id.encode()).hexdigest()[:8], 16))
        rng.shuffle(choices)

        r = jev[item_id]["reading"]
        jev_key = tuple(norm(r[f]) for f in FIELDS)
        jev_choice = next((c["option"] for c in choices if tuple(c["labels"][f] for f in FIELDS) == jev_key), None)

        qid = f"intent-{item_id}"
        options = [c["option"] for c in choices] + [UNCLEAR, SOMETHING_ELSE]
        option_labels = {c["option"]: c["labels"] for c in choices}
        option_labels.update(SPECIAL_LABELS)

        sections.append({
            "id": f"item-{item_id}",
            "title": f"{n} of {len(ITEMS)} · {spec['title']}",
            "markdown": scene_markdown(spec["scene"]),
            "questions": [{
                "id": qid,
                "number": f"Q{n}",
                "type": "single",
                "title": "What does the player mean?",
                "text": "The player types:\n\n> " + item["text"],
                "required": True,
                "options": options,
                "option_labels": option_labels,
                "follow_ups": [
                    {"id": "something-else", "label": "If something else: what do you think they mean?"},
                    {"id": "comment", "label": "Comment (optional)"},
                ],
            }],
        })
        mapping.append({
            "question_id": qid,
            "item_id": item_id,
            "category": item["category"],
            "why_ambiguous": CHOSEN[item_id],
            "choices": choices,
            "special": {UNCLEAR: "should_ask", SOMETHING_ELSE: "something_else: review by hand"},
            "jev_reading": {f: norm(r[f]) for f in FIELDS} | {"confidence": r["confidence"]},
            "jev_reading_is_choice": jev_choice,
            "gold_now": {f: item["gold"][f] for f in FIELDS},
        })

        founder_text = json.dumps(sections[-1]["markdown"]) + " ".join(options)
        for w in leak_words:
            assert not re.search(r"\b" + re.escape(w) + r"\b", founder_text), f"{item_id}: '{w}' leaks"

    sections.append({
        "id": "anything-else",
        "title": "Anything else?",
        "questions": [{
            "id": "patterns",
            "number": f"Q{len(ITEMS) + 1}",
            "type": "text",
            "long": True,
            "title": "Did you notice a pattern? When should the game just act, and when should it ask?",
            "required": False,
        }],
    })

    survey = {
        "format": 1,
        "id": SURVEY_ID,
        "version": 1,
        "status": "open",
        "active": True,
        "tab": "What did the player mean?",
        "title": "Founder survey 4: what did the player mean?",
        "estimated_minutes": 10,
        "intro": INTRO,
        "notes": [
            "**What it is:** 12 ambiguous player inputs from the intent eval set (ex-tales-forge PR #81, `test/fixtures/intent_eval/items.jsonl` at `b5af018`), **tune split only** (checked by `scripts/survey-intent/select_items.py`). No attack or safety items.",
            "**Choices:** each item offers 3–4 readings drawn from the item's gold label, its `acceptable` alternatives and Jev's readings (`scripts/survey-intent/jev-readings-2026-10-08.json`, jev-1.13.0, playtest key), deduped and shuffled. The survey never marks which one is the current gold; `scripts/survey-intent/mapping.json` does.",
            "**Labels:** `option_labels` on each question maps every option to structured labels (`action`, `target`, `when`, `later`, `later_target`; `reading` is `choice`, `should_ask` or `something_else`). The survey page never shows the key; the results page, the CSV (`<question>: labels`) and the Markdown export show it once [ex-tales-forge #82](https://github.com/whyse-ab/ex-tales-forge/pull/82) is merged.",
            "**Editing:** this JSON is generated by `scripts/survey-intent/build_survey.py`; edit `items_spec.py` and rebuild rather than editing here. Keep question ids stable and bump `version` if a choice's meaning changes.",
        ],
        "how_we_use": [
            "Answers become labels in the eval fixture, as described in [`scripts/survey-intent/apply_answers.md`](https://github.com/whyse-ab/tales-forge-docs/blob/main/docs/scripts/survey-intent/apply_answers.md): the majority reading becomes gold, a plausible minority reading becomes acceptable, and an 'Unclear' win or no majority marks the item as one the game should ask about.",
            "Per-item founder agreement sets how sure Jev must be before it acts without asking (the ask-band calibration).",
        ],
        "sections": sections,
    }

    with open(SURVEY_PATH, "w") as f:
        json.dump(survey, f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(MAPPING_PATH, "w") as f:
        json.dump({
            "survey_id": SURVEY_ID,
            "survey_version": 1,
            "fixture": "ex-tales-forge PR #81 test/fixtures/intent_eval/items.jsonl @ b5af018",
            "label_keys": LABEL_KEYS,
            "unclear_option": UNCLEAR,
            "something_else_option": SOMETHING_ELSE,
            "items": mapping,
        }, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {os.path.relpath(SURVEY_PATH, DOCS)} and mapping.json: {len(ITEMS)} items")


if __name__ == "__main__":
    main(sys.argv[1])
