"""Hand-written survey content for founder-survey-4-intent: per item, the scene
as the player knows it (trimmed from the fixture's context snapshot, no ids or
labels) and the suggested readings, each with the structured labels it stands
for. `build_survey.py` checks every label against the fixture's gold and
`acceptable_*` values and Jev's readings, shuffles, and writes the survey.

Label keys (the same for every choice):
  action        one of the 16 action types
  target        candidate id (npc / place / item / fixture) or None
  later         deferred action type, or None (nothing deferred)
  later_target  deferred action's candidate id, or None
`when` ("now" or "now, then later") is derived from `later` by the builder.
"""

INN = "the Valley Inn, in the common room"

ITEMS = {
    "r108": {
        "title": "Thanks, Brenna",
        "scene": {
            "where": INN,
            "here": "Brenna Holt (the innkeep), Rusk (a road thief) and Cobb (his brute)",
            "playing": "Taren Swiftbrook",
            "turns": [
                "I approach the bar with a nod and say, \"An old friend would be nice. I'm Taren Swiftbrook, just arrived from the wilds.\" …",
                "I take a sip of the ale and say, \"The orc nest sounds like the kind of work that needs doing. Tell me more about …\"",
            ],
            "game": "\"Osric's steward for the Tin Guild up in the market square,\" she says. \"Pays ten silver a head for every orc you bring proof of, more if you clear the whole nest that's blocking the cut.\" […] \"If you're of a mind, Osric's always there by midday.\"",
        },
        "choices": [
            ("Thanks Brenna and stays at the inn for now. Going to the square to see Osric is a plan for a later turn.",
             dict(action="speak", target="innkeep", later="move", later_target="market_square")),
            ("Thanks Brenna and walks up to the market square now.",
             dict(action="move", target="market_square", later=None, later_target=None)),
            ("Just finishes the ale and thanks Brenna. The square is only talk; nothing to remember.",
             dict(action="speak", target="innkeep", later=None, later_target=None)),
        ],
    },
    "r088": {
        "title": "Wrap the bread",
        "scene": {
            "where": INN,
            "here": "Brenna Holt (the innkeep), Rusk (a road thief) and Cobb (his brute)",
            "playing": "Hilde Stonebrook",
            "turns": [
                "I push back my hood, meeting Brenna's eyes steadily. \"Orcs are trouble, but I'm no sellsword. What else needs doing …\"",
                "I take a slow sip of the ale, nodding with quiet approval. \"Old Maude's withering herbs sound like something worth mending …\"",
            ],
            "game": "\"The old adit sits a half-mile up the western slope, just past the lightning-split pine. Maude says the ground there weeps black water that stinks of sulfur.\" […] \"If you're heading that way before dusk, mind the loose shale. Want me to wrap some bread for the walk? Two coppers.\"",
        },
        "choices": [
            ("Buys the bread from Brenna now. Heading up the slope is for a later turn.",
             dict(action="buy", target="innkeep", later="move", later_target=None)),
            ("Buys the bread now, and later heads to the old adit.",
             dict(action="buy", target="innkeep", later="move", later_target="old_adit")),
            ("Buys the bread. \"I'll head up before dusk\" is just talk; nothing to remember.",
             dict(action="buy", target="innkeep", later=None, later_target=None)),
        ],
    },
    "r109": {
        "title": "At first light",
        "scene": {
            "where": "Market Square, in the evening",
            "here": "Osric Vane (the Guild steward)",
            "playing": "Taren Swiftbrook",
            "turns": [
                "I sign the ledger and say, \"Done. I'll head out at first light and bring back their banner.\" …",
                "I grip the tin token and nod to Osric. \"I'll bring back that banner before dusk tomorrow.\" …",
            ],
            "game": "\"Before dusk tomorrow suits us fine, Swiftbrook. The nest sits in the cut just past the old watchpost, maybe a dozen warriors.\" […] \"First light, then. Mind the west road; it's grown restless of late.\"",
        },
        "choices": [
            ("Sets off now, sneaking out along the west road toward the watchpost.",
             dict(action="move", target="west_road", later=None, later_target=None)),
            ("Sneaks straight up to the orc nest this turn to scout it.",
             dict(action="move", target="orc_nest", later=None, later_target=None)),
            ("Heads for the cut above the nest (past the watchpost) this turn.",
             dict(action="move", target="orc_approach", later=None, later_target=None)),
            ("Waits for first light first; setting off down the west road comes after.",
             dict(action="wait", target=None, later="move", later_target="west_road")),
        ],
    },
    "r135": {
        "title": "Beside Caldern",
        "scene": {
            "where": "on the trail north of the mine workings, below the orc nest (the game still has you at the mine workings)",
            "here": "Caldern Voss (an old prospector, guiding you)",
            "playing": "Taren Swiftbrook",
            "turns": [
                "I'll head east through the stalls to the mine workings and find Caldern Voss right now to get the path to that orc nest.",
                "Caldern, lead the way up that trail to the orc nest. Let's clear it out together before dusk.",
            ],
            "game": "\"Fair enough, elf. Two hours north, keep low past the ridge line; scouts like to sit in the scrub.\" […] Voss slows, points to a faint game trail and whispers that the nest hollow lies just beyond the next crest. A distant scrape of metal on stone drifts down from above. He glances back at you, waiting for your next word or move.",
        },
        "choices": [
            ("Draws the knife and sneaks up beside Caldern now. Attacking the scouts is the next step.",
             dict(action="move", target="orc_approach", later="combat", later_target=None)),
            ("Attacks the scouts right now.",
             dict(action="combat", target=None, later=None, later_target=None)),
            ("Whispers the plan to Caldern and stays put; the attack comes later.",
             dict(action="speak", target="prospector", later="combat", later_target=None)),
        ],
    },
    "r093": {
        "title": "Knife under the bench",
        "scene": {
            "where": INN + ", mid-fight",
            "here": "Cobb (Rusk's brute, with a club), Rusk (a road thief) and Brenna Holt (the innkeep)",
            "playing": "Brannoc Hale",
            "turns": [
                "I keep my stance balanced and eyes locked on Cobb, hand hovering near my knife, and say firmly, \"Last warning. Back off …\"",
                "I draw my hunting knife in a smooth motion, sidestep the incoming club swing, and counter with a quick thrust at Cobb … (it failed)",
            ],
            "game": "The impact sends the blade spinning from your grip; it slides under a bench. […] Brenna's voice cracks like a whip: \"Outside, you louts!\" Cobb snarls and hefts the club again, ready to press the advantage while you're disarmed. The door to the inn yard stands open a crack.",
        },
        "choices": [
            ("A fighting move: grabs the knife and keeps Cobb at bay, dodging his club.",
             dict(action="combat", target="cobb", later=None, later_target=None)),
            ("Grabs the knife and retreats out into the inn yard this turn.",
             dict(action="move", target="inn_yard", later=None, later_target=None)),
            ("Just gets the knife back; no attack and no leaving yet.",
             dict(action="pickup", target="hunting_knife", later=None, later_target=None)),
        ],
    },
    "h-q11": {
        "title": "That short sword",
        "scene": {
            "where": "Brask's forge",
            "here": "Hilde Brask (the smith). Her rack holds short swords, hunting knives and spearheads",
            "playing": "a traveller",
            "turns": [],
            "game": "Brask's forge glows hot; Hilde sets down her hammer by the rack of blades.",
        },
        "choices": [
            ("Asks Hilde the price. No buying yet.",
             dict(action="speak", target="smith", later=None, later_target=None)),
            ("Buys the short sword.",
             dict(action="buy", target="short_sword", later=None, later_target=None)),
            ("Asks the price now, meaning to buy it next.",
             dict(action="speak", target="smith", later="buy", later_target="short_sword")),
        ],
    },
    "h-m14": {
        "title": "A round for the miners",
        "scene": {
            "where": INN,
            "here": "Brenna Holt (the innkeep, sells ale at 2 copper), Rusk (a road thief) and Cobb (his brute)",
            "playing": "a traveller",
            "turns": [],
            "game": "The hearth crackles in the common room of the Valley Inn; Brenna wipes mugs while Rusk and Cobb watch from the bar.",
        },
        "choices": [
            ("Buys a round of ale from Brenna, then asks about the lights.",
             dict(action="buy", target="ale_mug", later=None, later_target=None)),
            ("Mainly asks about the lights; the round is just a friendly gesture.",
             dict(action="speak", target=None, later=None, later_target=None)),
            ("Buys a round for the men at the bar, Rusk and Cobb, and asks them.",
             dict(action="buy", target="cobb", later=None, later_target=None)),
        ],
    },
    "h-p12": {
        "title": "Rope first",
        "scene": {
            "where": "Market Square, with its market stalls and the Guild post",
            "here": "Osric Vane (the Guild steward)",
            "playing": "a traveller",
            "turns": [],
            "game": "Market Square smells of mud and ore-carts; Osric Vane stands by the guild post, the bounty parchment in hand.",
        },
        "choices": [
            ("Buys rope at a stall now. Heading up to the cut is for a later turn.",
             dict(action="buy", target=None, later="move", later_target="orc_approach")),
            ("Buys rope at a stall now; \"then the cut\" is just talk.",
             dict(action="buy", target=None, later=None, later_target=None)),
            ("Asks Osric where to get rope, then heads for the cut later.",
             dict(action="speak", target="guild_steward", later="move", later_target="orc_approach")),
            ("Buys rope at a stall now, planning to fight at the cut next.",
             dict(action="buy", target="stalls", later="combat", later_target=None)),
        ],
    },
    "r197": {
        "title": "The scrape in the dark",
        "scene": {
            "where": "inside the mine, in a low chamber off the third drift",
            "here": "Caldern Voss (the prospector)",
            "playing": "Taren Swiftbrook",
            "turns": [
                "I'll take the lamp for two copper, Caldern, then head into the mine to find and clear that orc nest.",
                "I light the lamp and head carefully into the mine, knife drawn, following the third drift toward the orc nest.",
            ],
            "game": "The tunnel bends left, then opens into a low chamber. Drag marks scar the floor, and the faint stink of wet hides and old blood hangs in the still air. Something scrapes stone deeper in the dark beyond the reach of your light.",
        },
        "choices": [
            ("Creeps forward quietly, looking for whatever is scraping. No attack yet.",
             dict(action="observe", target=None, later=None, later_target=None)),
            ("Sneaks on toward the orc nest itself.",
             dict(action="move", target="orc_nest", later=None, later_target=None)),
            ("Ambushes the orc now.",
             dict(action="combat", target=None, later=None, later_target=None)),
            ("Creeps and scouts now; the ambush is the next turn.",
             dict(action="observe", target=None, later="combat", later_target=None)),
        ],
    },
    "h-q15": {
        "title": "Pay the toll",
        "scene": {
            "where": INN,
            "here": "Brenna Holt (the innkeep), Rusk (a road thief known for his 'tolls') and Cobb (his brute)",
            "playing": "a traveller",
            "turns": [],
            "game": "The hearth crackles in the common room of the Valley Inn; Brenna wipes mugs while Rusk and Cobb watch from the bar.",
        },
        "choices": [
            ("Grumbles under their breath and doesn't pay. Just flavour.",
             dict(action="other", target=None, later=None, later_target=None)),
            ("Says it to Rusk's face, mocking him and refusing to pay.",
             dict(action="speak", target="rusk", later=None, later_target=None)),
            ("Doesn't pay yet, but means to pay Rusk later.",
             dict(action="other", target=None, later="spend", later_target="rusk")),
            ("Pays Rusk the toll.",
             dict(action="spend", target="rusk", later=None, later_target=None)),
        ],
    },
    "r074": {
        "title": "The bellows and the bow",
        "scene": {
            "where": "Brask's forge, in the evening",
            "here": "Hilde Brask (the smith)",
            "playing": "Taren Swiftbrook",
            "turns": [
                "Go to the forge now",
                "I'll pump the bellows for you tonight if it drops the price to eight silver. Then tell me what you make of those unstamped …",
            ],
            "game": "\"Aye, that bow I mentioned: eight silver if you work the bellows with me tonight.\" […] \"Rusk's men bring me the cheap stuff after dark. I'd sleep better if he weren't around to squeeze the town. You clear him out, and I'll sharpen your blade for nothing next time.\"",
        },
        "choices": [
            ("Agrees to the bellows deal and asks about Rusk. Just talk; nothing changes hands yet.",
             dict(action="speak", target="smith", later=None, later_target=None)),
            ("Strikes the trade now: bellows work for the bow at eight silver.",
             dict(action="trade", target="smith", later=None, later_target=None)),
            ("Buys the bow for eight silver now.",
             dict(action="buy", target="smith", later=None, later_target=None)),
            ("Asks where Rusk is now, then goes after him.",
             dict(action="speak", target="smith", later="move", later_target="rusk")),
        ],
    },
    "r204": {
        "title": "Into the square",
        "scene": {
            "where": "the door of the Valley Inn, just stepping out (the game still has you at the inn)",
            "here": "Brenna Holt (the innkeep), behind you",
            "playing": "Hilde Stonebrook",
            "turns": [
                "I grunt, tearing another piece of bread. \"Then I'll head to the square myself and give Osric your warning.\" …",
                "I nod thanks to Brenna for the bundle, tuck it under my cloak, and head for the door. \"I'll bring word back if the Guild …\"",
            ],
            "game": "You push the heavy door open and step out into the crisp night air of the valley. The lanterns of Market Square flicker ahead down the rutted path. Osric Vane and his spears are still out there.",
        },
        "choices": [
            ("Walks into the market square now and calls out the warning to Osric on arrival.",
             dict(action="move", target="market_square", later=None, later_target=None)),
            ("Calls out to Osric as if he were already in earshot.",
             dict(action="speak", target="guild_steward", later=None, later_target=None)),
            ("Walks to the square now; the warning to Osric is the next turn.",
             dict(action="move", target="market_square", later="speak", later_target="guild_steward")),
        ],
    },
}
