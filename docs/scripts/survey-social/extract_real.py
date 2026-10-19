#!/usr/bin/env python3
"""Pick the real lines (items_spec.REAL) out of the read-only turn dump.

    python3 extract_real.py <real_turns.out> > real_items.json

`real_turns.out` is the psql output of `real_turns.sql` (playtest DB,
BEGIN READ ONLY ... ROLLBACK). The dump itself is not committed: only the
player's line, the player's line before it and the tail of the GM narration
before it (what the founder sees) are kept. Player-character names are never read; the session id and
turn number stay so the line can be traced (in the stored data only).
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from items_spec import REAL  # noqa: E402

SNIPPET_MAX = 420


def turns(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.search(r"TURN\|(\{.*)$", line)
        if m:
            t = json.loads(m.group(1))
            out[(t["s"], t["n"])] = t
    return out


def snippet(narration):
    """The last sentences of the narration, at most SNIPPET_MAX characters."""
    text = re.sub(r"\s+", " ", narration).strip()
    if len(text) <= SNIPPET_MAX:
        return text
    tail = text[-SNIPPET_MAX:]
    starts = [m.end() for m in re.finditer(r'[.!?]["”]?\s+(?=["“A-Z])', tail)]
    return "[…] " + (tail[starts[0]:] if starts else tail)


def main(path):
    by = turns(path)
    items = []
    for spec in REAL:
        t = by[(spec["session"], spec["turn"])]
        prev = by[(spec["session"], spec["turn"] - 1)]
        items.append({"key": spec["key"], "session": spec["session"], "turn": spec["turn"],
                      "at": t["at"], "line": t["text"], "prev_line": prev["text"],
                      "game_said": snippet(prev["narr"])})
    json.dump(items, sys.stdout, ensure_ascii=False, indent=2)
    print()


if __name__ == "__main__":
    main(sys.argv[1])
