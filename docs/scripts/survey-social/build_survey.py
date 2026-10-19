#!/usr/bin/env python3
"""Build docs/founder-survey-5-social.json and mapping.json.

Usage (from docs/scripts/survey-social in ex-tales-forge):

    # real_turns.sql, read-only, on the playtest DB -> real_turns.out (not committed)
    python3 extract_real.py real_turns.out > real_items.json
    python3 build_survey.py
    python3 ../survey/render_md.py ../../founder-survey-5-social.json > ../../founder-survey-5-social.md
    cp ../../founder-survey-5-social.json ../../../priv/surveys/

The same mechanism as founder survey 4 (`scripts/survey-intent/`): one JSON in
docs/, read by the app from main; `option_labels` map each option to a label
the founders never see. Each section also carries `origin` ("real" or
"scripted") and `source`; the app ignores both keys, so they are in the
stored file (and its SHA-256 in `survey_definitions`) but never on the page.

Checks, each fatal:
  * 24 real + 16 scripted lines, every key once;
  * every target option names someone present, or is everyone / no one / unclear;
  * no internal word (scripted, covers, session ids, Jev) in what founders read.

Lines are shuffled with a seed from the survey id, so a rebuild gives the same
order and real and scripted lines are mixed.
"""

import hashlib
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from items_spec import PEOPLE, REAL, SCRIPTED  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.normpath(os.path.join(HERE, "..", ".."))
SURVEY_ID = "founder-survey-5-social"
SURVEY_PATH = os.path.join(DOCS, SURVEY_ID + ".json")
MAPPING_PATH = os.path.join(HERE, "mapping.json")
REAL_PATH = os.path.join(HERE, "real_items.json")

# The 14 social-act labels of docs/analysis-social-levers.md (PR #479, G1), in
# its order, plus "unclear". The one-line descriptions are the ones Jev must get
# in the later comparison, word for word.
SOCIAL_ACTS = [
    ("none", "None: no social act toward anyone (an action, a look, waiting)"),
    ("request", "Request: asks someone to do, give or tell something (questions and orders count)"),
    ("offer", "Offer: proposes a deal or help (something for something, or a price)"),
    ("gift", "Gift: gives something freely, nothing asked back"),
    ("thanks", "Thanks: thanks someone"),
    ("compliment", "Compliment: sincere praise"),
    ("flattery", "Flattery: praise used to get something (a discount, a favour)"),
    ("joke", "Joke: meant to be funny, friendly teasing included"),
    ("insult", "Insult: puts someone down, mocks or offends them"),
    ("threat", "Threat: warns of harm unless they do, or stop doing, something"),
    ("apology", "Apology: says sorry or makes amends"),
    ("promise", "Promise: commits to do something later"),
    ("claim", "Claim: states something as fact, to be believed (true or not)"),
    ("refusal", "Refusal: says no to a request, an offer or a demand"),
    ("unclear", "Unclear: two or more of these fit equally well"),
]

# The voice levels of docs/experiments/2026-10-two-step-jev.md (PR #481, step 1
# `voice`), in its words, plus "unclear".
VOICE = [
    ("whisper", "Whisper: whispers or speaks under the breath, meant for one person close by"),
    ("talk", "Talk: ordinary speaking voice"),
    ("shout", "Shout: shouts, calls out across a room or street, or raises the voice"),
    ("none", "None: says nothing aloud (a silent action)"),
    ("unclear", "Unclear"),
]

EVERYONE = "Everyone here (the whole room or group)"
NO_ONE = "No one in particular"
UNCLEAR_TARGET = "Unclear"

INTRO = (
    "Hi! Before the people in the game can react to what a player says, the game has to "
    "know what the line **does** to them: is it a joke or an insult, flattery or honest "
    "praise, a threat or just a warning? Who is it aimed at, and how loud is it?\n\n"
    "Here are 40 player lines, each with the scene and what the game said just before. "
    "For each line, pick three things:\n\n"
    "1. **What the line does**: one of 14 kinds, or **Unclear** when two or more fit "
    "equally well (a useful answer, not a failure).\n"
    "2. **Who it is aimed at**: one of the people present, everyone, or no one.\n"
    "3. **How loud**: whisper, talk, shout, or nothing said aloud.\n\n"
    "Go with your gut, as a player; this is not a test. Answer on your own, and please "
    "don't open the results page until you are done: it shows the others' answers. "
    "About 20 minutes.\n\n"
    "Answers save as you go, and you can change them until the survey closes."
)

NOTES = [
    "**What it is:** 40 player lines, 24 real and 16 scripted, for the G1 social-act "
    "experiment in [`analysis-social-levers.md`](analysis-social-levers.md) "
    "(PR #479). The plan, the proposed pass bar and the later comparison are in "
    "[`experiments/2026-10-social-act-survey.md`](experiments/2026-10-social-act-survey.md).",
    "**Real lines:** every player line is from a 2026-10-18 playtest session (prod had no "
    "turns that day), read inside `BEGIN READ ONLY … ROLLBACK` with "
    "`scripts/survey-social/real_turns.sql`. Only the player's line, the line before it and "
    "the tail of the GM narration before it are kept; the player character's name is never "
    "shown (\"a traveller\").",
    "**Scripted lines:** 16 lines written to cover what the real ones lack: insults, jokes, "
    "threats, flattery, apologies, sarcasm, whispers and shouts. Each section's `origin` "
    "(`real` or `scripted`) and `source` say which is which; the app ignores both keys, so "
    "founders never see them. `scripts/survey-social/mapping.json` lists them too, with what "
    "each scripted line was written to cover (not a gold label).",
    "**Blind:** no Jev reading is shown or stored here, and Jev has not been run on these "
    "lines. Each founder sees only their own answers on the survey page.",
    "**Labels:** `option_labels` map every option to `social_act`, `target` (a character "
    "slug, `everyone`, `no_one`, or null for unclear) or `voice`. The 14 act labels are G1's; "
    "the voice levels are step 1's `voice` from PR #481 (`docs/experiments/2026-10-two-step-jev.md`).",
    "**Editing:** this JSON is generated by `scripts/survey-social/build_survey.py`; edit "
    "`items_spec.py` and rebuild rather than editing here. Keep question ids stable and bump "
    "`version` if an option's meaning changes.",
]

HOW_WE_USE = [
    "Per line, the founder majority on each of the three questions becomes the label; "
    "no majority, or an \"Unclear\" win, marks the line as one the game should not act on "
    "with confidence.",
    "Founder-to-founder agreement is the ceiling. Jev is then run on the same lines and "
    "scored against the majority, against the pass bar Fredrik sets before the run "
    "([the experiment doc](experiments/2026-10-social-act-survey.md)).",
]


def fail(message):
    sys.exit(f"build_survey.py: {message}")


def items():
    real = {r["key"]: r for r in json.load(open(REAL_PATH, encoding="utf-8"))}
    out = []
    for spec in REAL:
        r = real[spec["key"]]
        if (r["session"], r["turn"]) != (spec["session"], spec["turn"]):
            fail(f"{spec['key']}: real_items.json is stale; rerun extract_real.py")
        out.append({**spec, "origin": "real", "line": r["line"], "prev_line": r["prev_line"],
                    "game_said": r["game_said"], "at": r["at"]})
    out += [{**s, "origin": "scripted"} for s in SCRIPTED]
    keys = [i["key"] for i in out]
    if len(set(keys)) != len(keys) or (len(REAL), len(SCRIPTED)) != (24, 16):
        fail("expected 24 real and 16 scripted lines, every key once")
    seed = int(hashlib.sha1(SURVEY_ID.encode()).hexdigest()[:8], 16)
    random.Random(seed).shuffle(out)
    return out


def quote(text):
    return "\n".join("> " + line if line else ">" for line in text.split("\n"))


def who(present):
    names = [PEOPLE[p] for p in present]
    return names[0] if len(names) == 1 else ", ".join(names[:-1]) + " and " + names[-1]


def section_markdown(item):
    return "\n".join([
        f"**Where:** {item['where']}.  ",
        f"**Who's here:** {who(item['present'])}.  ",
        "**The player is:** a traveller.",
        "",
        f"**The player's turn before:** {item['prev_line']}",
        "",
        "**The game just said:**",
        "",
        quote(item["game_said"]),
        "",
        "**Now the player types:**",
        "",
        quote(item["line"]),
    ])


def target_question(nn, number, present):
    options = [PEOPLE[p] for p in present] + [EVERYONE, NO_ONE, UNCLEAR_TARGET]
    labels = {PEOPLE[p]: {"target": p} for p in present}
    labels.update({EVERYONE: {"target": "everyone"}, NO_ONE: {"target": "no_one"},
                   UNCLEAR_TARGET: {"target": None}})
    return {"id": f"target-{nn}", "number": f"{number}b", "type": "single",
            "title": "Who is it aimed at?", "required": True,
            "options": options, "option_labels": labels}


def section(position, item):
    nn = f"{position:02d}"
    number = f"Q{position}"
    return {
        "id": f"line-{nn}",
        "title": f"{position} of 40 · {item['title']}",
        "origin": item["origin"],
        "source": source(item),
        "markdown": section_markdown(item),
        "questions": [
            {"id": f"act-{nn}", "number": f"{number}a", "type": "single",
             "title": "What does the line do?", "required": True,
             "options": "@social_acts",
             "option_labels": {text: {"social_act": label} for label, text in SOCIAL_ACTS},
             "follow_ups": [{"id": "comment", "label": "Comment (optional)"}]},
            target_question(nn, number, item["present"]),
            {"id": f"voice-{nn}", "number": f"{number}c", "type": "single",
             "title": "How loud?", "required": True, "options": "@voice",
             "option_labels": {text: {"voice": label} for label, text in VOICE}},
        ],
    }


def source(item):
    if item["origin"] == "real":
        return {"kind": "real", "env": "playtest", "date": "2026-10-18",
                "session": item["session"], "turn": item["turn"], "key": item["key"]}
    return {"kind": "scripted", "key": item["key"], "covers": item["covers"]}


def founder_text(survey):
    parts = [survey["intro"]]
    for s in survey["sections"]:
        parts += [s["title"], s.get("markdown", "")]
        for q in s["questions"]:
            parts += [q["title"], q.get("text", "")] + [f["label"] for f in q.get("follow_ups", [])]
            if isinstance(q.get("options"), list):
                parts += q["options"]
    parts += [x for v in survey["lists"].values() for x in v]
    return "\n".join(parts)


def check_no_leaks(survey, its):
    text = founder_text(survey).lower()
    words = ["scripted", "covers", "jev", "origin", "qaretest", "elara"]
    words += [i["session"][:8] for i in its if i["origin"] == "real"]
    leaked = [w for w in words if w in text]
    if leaked:
        fail(f"internal words in what founders read: {leaked}")


def build():
    its = items()
    sections = [section(n, i) for n, i in enumerate(its, 1)]
    sections.append({"id": "anything-else", "title": "Anything else?", "questions": [
        {"id": "hard-pairs", "number": "Q41", "type": "text", "long": True, "required": False,
         "title": "Which kinds were hard to tell apart, and why?"}]})
    survey = {
        "format": 1, "id": SURVEY_ID, "version": 1, "status": "open", "active": True,
        "tab": "What does the line do?",
        "title": "Founder survey 5: what does the player's line do?",
        "estimated_minutes": 20, "intro": INTRO, "notes": NOTES, "how_we_use": HOW_WE_USE,
        "lists": {"social_acts": [t for _, t in SOCIAL_ACTS], "voice": [t for _, t in VOICE]},
        "sections": sections,
    }
    check_no_leaks(survey, its)
    mapping = {
        "survey_id": SURVEY_ID, "survey_version": 1,
        "social_acts": [label for label, _ in SOCIAL_ACTS],
        "voice": [label for label, _ in VOICE],
        "counts": {"real": len(REAL), "scripted": len(SCRIPTED)},
        "items": [{"position": n, "section_id": f"line-{n:02d}",
                   "question_ids": [f"act-{n:02d}", f"target-{n:02d}", f"voice-{n:02d}"],
                   **source(i), "present": i["present"], "line": i["line"]}
                  for n, i in enumerate(its, 1)],
    }
    for path, data in [(SURVEY_PATH, survey), (MAPPING_PATH, mapping)]:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
    print(f"wrote {SURVEY_PATH} ({len(its)} lines) and {MAPPING_PATH}")


if __name__ == "__main__":
    build()
