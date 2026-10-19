"""The lines of founder survey 5 (social acts): 24 real, 16 scripted.

REAL: player lines from the 2026-10-18 playtest sessions (prod had no turns
that day). The line and the GM snippet come from the read-only dump through
extract_real.py (real_items.json); this file only says which turns, where the
scene is and who is present. Presence is from the transcript state lines
(docs/playtests/2026-10-18-10e-after/transcript.md) for session 3705591b, and
from the GM narration of the turn before and of the line's own turn for the
others. The player's character is shown only as "a traveller": the quick-start
and QA character names are left out.

SCRIPTED: written for this survey to cover what the real lines lack (insults,
jokes, threats, flattery, apologies, sarcasm, whispers and shouts). `covers` is
what the line was written to test. It is NOT a gold label: the founders'
majority is the label. Founders never see `covers` or which lines are scripted.

People: a slug and how the survey names them. `everyone` and `no_one` are
added to every target question.
"""

PEOPLE = {
    "innkeep": "Brenna Holt (the innkeep)",
    "rusk": "Rusk (a road thief)",
    "cobb": "Cobb (Rusk's brute)",
    "smith": "Hilde Brask (the smith)",
    "herb_wife": "Old Maude (the herb-wife)",
    "guild_steward": "Osric Vane (the Guild steward)",
    "pip": "Pip (Maude's grandson)",
    "stable_lad": "Tam Holt (the stable lad)",
}

INN = "the Valley Inn, in the common room"
FORGE = "Brask's forge, off the Market Square"
COTTAGE = "Old Maude's herb cottage, off the Market Square"
ADIT = "the old adit on the west road, at night"
SQUARE = "the Market Square, in the evening"

S_AFTER = "3705591b-f2f8-4f03-8114-fca1368b6ff1"
S_253 = "253e26a5-e4ab-46cb-b472-7af6cdb3c25d"
S_3A2 = "3a27fdde-e89d-4d82-a093-062ff8e15129"
S_464 = "464229eb-4376-4cfc-8d8b-6e5e58b9e2b1"
S_643 = "643b8031-771d-42af-a63f-ddebbfe1ba82"
S_6D9 = "6d938a30-aaa6-46cf-8db8-f7e6f8c28f39"
S_9A9 = "9a971f8d-dd18-4af8-a835-7a77eb1aaf08"

BRENNA = ["innkeep"]
INN_CROWD = ["innkeep", "rusk", "cobb"]


def real(key, session, turn, title, where, present):
    return dict(key=key, session=session, turn=turn, title=title, where=where, present=present)


REAL = [
    real("r01", S_AFTER, 2, "Good evening", INN, BRENNA),
    real("r02", S_AFTER, 3, "A silver for Thistle", INN, BRENNA),
    real("r03", S_253, 2, "What work is there?", INN, BRENNA),
    real("r04", S_253, 3, "How much for a mug?", INN, BRENNA),
    real("r05", S_253, 6, "The cloak", INN, INN_CROWD),
    real("r06", S_3A2, 2, "How's business?", INN, BRENNA),
    real("r07", S_464, 2, "A cheaper mug", INN, BRENNA),
    real("r08", S_AFTER, 19, "Ten copper for the knife", FORGE, ["smith"]),
    real("r09", S_AFTER, 20, "Lend me a sword", FORGE, ["smith"]),
    real("r10", S_AFTER, 21, "One copper", FORGE, ["smith"]),
    real("r11", S_AFTER, 24, "The open hand", COTTAGE, ["herb_wife"]),
    real("r12", S_AFTER, 25, "The rope", COTTAGE, ["herb_wife"]),
    real("r13", S_AFTER, 28, "The toll", ADIT, ["rusk", "cobb"]),
    real("r14", S_AFTER, 33, "Stitches", COTTAGE, ["herb_wife"]),
    real("r15", S_AFTER, 36, "Do you remember?", INN + ", late at night", BRENNA),
    real("r16", S_6D9, 2, "A plain yes", INN, BRENNA),
    real("r17", S_6D9, 4, "No, thank you", INN, BRENNA),
    real("r18", S_6D9, 6, "The stew", INN, BRENNA),
    real("r19", S_6D9, 9, "Stretch and yawn", INN, INN_CROWD),
    real("r20", S_6D9, 10, "Yes again", INN, INN_CROWD),
    real("r21", S_6D9, 13, "Yes in the square", SQUARE, ["guild_steward"]),
    real("r22", S_6D9, 15, "Three hundred mugs", INN, BRENNA),
    real("r23", S_9A9, 2, "Knife in hand", INN, BRENNA),
    real("r24", S_643, 7, "Rusk", INN, INN_CROWD),
]


# The player's turn before each scripted line (shown like a real line's).
PREV_LINES = {
    "s01": "I sit at a table near the hearth with my ale.",
    "s02": "I order a bowl of stew.",
    "s03": "I sit on the bench by the door and finish my ale.",
    "s04": "I ask the smith how much the short sword costs.",
    "s05": "I walk up to the bar and order an ale.",
    "s06": "I ask Osric what the Guild pays.",
    "s07": "I walk up to the bar.",
    "s08": "I push my way to the long benches.",
    "s09": "I attack Cobb with my knife.",
    "s10": "I let Maude look at my wound.",
    "s11": "I tell Osric I'll take the job.",
    "s12": "I walk into the forge.",
    "s13": "I walk over to Rusk's table.",
    "s14": "I walk up the road toward the adit.",
    "s15": "I sit down at the bar.",
    "s16": "I wait in the inn yard.",
}


def scripted(key, covers, title, where, present, game_said, line):
    return dict(key=key, covers=covers, title=title, where=where, present=present,
                prev_line=PREV_LINES[key], game_said=game_said, line=line)


SCRIPTED = [
    scripted("s01", ["insult"], "Spilled ale", INN + ", in the evening", INN_CROWD,
             "Cobb shoulders past your table, slopping ale across your sleeve, and grunts something "
             "that might be an apology or might not. Rusk laughs from the corner table.",
             'I wipe my sleeve and say to Cobb, "You smell like the back end of a mule, and you drink like one too."'),
    scripted("s02", ["joke"], "Thick stew", INN, BRENNA,
             "Brenna sets a bowl in front of you, the stew so thick the spoon stands up on its own. "
             '"Hot and filling," she says. "Five copper, love."',
             'I poke the spoon and grin. "Brenna, if this stew gets any thicker I\'ll need a pick from the cut to eat it."'),
    scripted("s03", ["threat"], "The purse", INN + ", in the evening", INN_CROWD,
             "Rusk drifts past your bench, and a moment later your purse hangs lighter on its string. "
             "He settles back at his table, smiling at nobody.",
             'I rest my hand on my knife and say to Rusk, "Touch my purse again and you\'ll be counting your fingers."'),
    scripted("s04", ["flattery"], "The finest smith", FORGE, ["smith"],
             'Hilde sets a short sword on the anvil. "Six silver, and that\'s the price. I don\'t haggle at this hour."',
             '"Everyone from here to Kestrel Ford says yours are the finest blades in the valley, Hilde. '
             'Surely the finest smith can find a better price for a friend?"'),
    scripted("s05", ["apology"], "Last night", INN + ", the morning after a quarrel", BRENNA,
             'Brenna serves you without her usual smile. "Ale\'s two copper," she says, and turns away '
             "before you can answer. Last night's sharp words still hang between you.",
             '"I\'m sorry for what I said last night, Brenna. That was the ale talking, and you didn\'t deserve it."'),
    scripted("s06", ["sarcasm"], "Five silver a week", SQUARE, ["guild_steward"],
             'Osric taps his ledger. "Five silver a week, a spear, and you bring your own boots. '
             'The orcs won\'t wait for you to make up your mind."',
             '"Five silver a week to fight orcs? My, how generous the Guild is."'),
    scripted("s07", ["whisper", "request"], "The man in the corner", INN + ", busy tonight", INN_CROWD,
             "The common room is loud with miners. Rusk and Cobb sit at the corner table, watching the "
             "door. Brenna wipes the bar right next to you.",
             'I lean over the bar and whisper to Brenna, "Is that man in the corner the one robbing the salt carts?"'),
    scripted("s08", ["shout", "gift", "offer"], "A round for the room", INN + ", packed tonight", INN_CROWD,
             "The common room is packed; miners sit shoulder to shoulder at the long benches, and Brenna "
             "can barely keep the mugs coming.",
             'I climb onto the bench and shout, "A round for the whole room, on me!"'),
    scripted("s09", ["shout", "insult", "threat"], "Up the slope", ADIT, ["rusk", "cobb"],
             'Rusk and Cobb have pulled back up the slope behind the rotten timbers, out of reach. '
             '"Road\'s still ours, stranger," Rusk calls down.',
             'I shout up the slope, "Come down here and face me, you cowards!"'),
    scripted("s10", ["compliment", "thanks"], "Healing clean", COTTAGE, ["herb_wife"],
             'Maude unwraps the bandage and peers at the cut on your arm. "Healing clean," she says. '
             '"Keep it dry another day."',
             '"Your poultice worked wonders, Maude. You have better hands than any surgeon in the city."'),
    scripted("s11", ["promise"], "Before the full moon", SQUARE, ["guild_steward"],
             'Osric slides the ledger across to you. "Sign, and the Guild expects that nest cleared. When?"',
             'I sign and say, "You have my word. The nest will be clear before the next full moon."'),
    scripted("s12", ["claim", "request"], "On the Guild's account", FORGE, ["smith"],
             'Hilde looks up from the bellows. "You again. Coin first, then steel."',
             '"Osric Vane sent me. He said you\'d give me a sword on the Guild\'s account."'),
    scripted("s13", ["whisper", "threat"], "Leave the boy out of it", INN + ", late in the evening",
             ["innkeep", "rusk", "cobb", "pip"],
             "Pip, Maude's grandson, sits hunched beside Rusk, staring into his mug while Rusk talks low "
             "in his ear about the west road.",
             'I lean close to Rusk and murmur, "Leave the boy out of your night work, or the Guild learns where you sleep."'),
    scripted("s14", ["refusal"], "Five silver to pass", ADIT, ["rusk", "cobb"],
             '"Five silver to pass," Rusk says, "or Cobb here gets to practise his swing. Your choice, stranger."',
             '"I\'m not paying you a single copper. Step aside."'),
    scripted("s15", ["sarcasm", "insult", "joke"], "Lovely club", INN + ", in the evening", INN_CROWD,
             "Cobb thumps his knotted club on the table and glares at you across the room.",
             '"Lovely club, Cobb. Did you carve it yourself, or did it carve you?"'),
    scripted("s16", ["shout", "thanks", "promise"], "Thistle comes home", "the inn yard of the Valley Inn, at dusk",
             ["pip", "stable_lad"],
             "Pip presses your lost mule's halter into your hand and is already running for the gate. "
             "Tam the stable lad leads the mule to a stall.",
             'I call after Pip, "Thank you, lad! I won\'t forget this!"'),
]
