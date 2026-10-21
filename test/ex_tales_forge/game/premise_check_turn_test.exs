defmodule TalesForge.Game.PremiseCheckTurnTest do
  @moduledoc """
  Characterization of the premise check's kill subjects and claim order
  before round 2 PR 4. The turn cases run the player text through the public
  turn path with TURN_PREMISE_FIRST on and no LLM calls (`Turn.new/3`,
  `Turn.Premise.check/1`) in a fresh tin_valley session, and pin every
  finding's claim and correction.
  """
  use TalesForge.DataCase, async: false

  alias TalesForge.Game.PremiseCheck
  alias TalesForge.Game.Schemas.{PlayerAction, SingleAction}
  alias TalesForge.Game.Turn
  alias TalesForge.GameSessions

  defp findings(session, text) do
    action = %PlayerAction{overall_intent: text, action: %SingleAction{action_type: :other}}
    flags = Map.put(Turn.read_flags(), :turn_premise_first, true)

    {session, 1}
    |> Turn.new({text, action}, flags: flags, role: :playtest)
    |> Turn.Premise.check()
    |> then(& &1.premise.first)
    |> Enum.map(&{&1.kind, &1.claim, &1.correction})
  end

  # {text, findings} through the turn, from main
  @turn_cases [
    {"I killed Brenna Holt last night, so I want her inn.",
     [
       {:kill, "killed Brenna Holt",
        "Player claims to have killed Brenna Holt; they have won no fight this session and Brenna Holt is alive. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I killed the orcs in the nest, pay me the bounty.",
     [
       {:kill, "killed the orcs",
        "Player claims to have killed the orcs; they have won no fight this session and Orc nest in the cut is still active. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I killed the dragon of Kestrel Ford.",
     [
       {:kill, "killed the dragon",
        "Player claims to have killed the dragon; they have won no fight this session and nobody by that name is known in this session. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I killed a rat in the cellar.", []},
    {"I killed Osric Vane and Cobb.",
     [
       {:kill, "killed Osric Vane",
        "Player claims to have killed Osric Vane; they have won no fight this session and Osric Vane is alive. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I pay with my gold crown, then I hand Brenna my sword and I put on my plate armour. I killed Cobb at midnight.",
     [
       {:item, "gold crown",
        "Player claims to own gold crown; they don't (they carry: travel cloak, hunting knife). Don't narrate it as true."},
       {:item, "plate armour",
        "Player claims to own plate armour; they don't (they carry: travel cloak, hunting knife). Don't narrate it as true."},
       {:kill, "killed Cobb",
        "Player claims to have killed Cobb; they have won no fight this session and nobody by that name is known in this session. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I bought a horse yesterday and I give Brenna my lantern from my pack.", []},
    {"I said I killed Cobb. Maybe I have a sword.", []},
    {"It is noon and I have 50 gold coins, I am wearing my chainmail and I bought a pony.",
     [
       {:time, "it is noon",
        "Player claims it is noon; the clock says Day 1 · late afternoon. Narrate the late afternoon. Don't narrate it as true."},
       {:coins, "50 gold",
        "Player claims to have 50 gold; they have 2 gold, 10 silver. Don't narrate it as true."}
     ]}
  ]

  # {text, claims in order}, from main
  @claim_cases [
    {"I killed Brenna Holt last night, so I want her inn.",
     [%{target: "Brenna Holt", kind: :kill}]},
    {"I killed the orcs in the nest, pay me the bounty.", [%{target: "the orcs", kind: :kill}]},
    {"I killed the dragon of Kestrel Ford.", [%{target: "the dragon", kind: :kill}]},
    {"I killed a rat in the cellar.", [%{target: "a rat", kind: :kill}]},
    {"I killed Osric Vane and Cobb.", [%{target: "Osric Vane", kind: :kill}]},
    {"I pay with my gold crown, then I hand Brenna my sword and I put on my plate armour. I killed Cobb at midnight.",
     [
       %{item: "gold crown", kind: :item, noun: "crown", quantity: nil},
       %{item: "sword", kind: :item, noun: "sword", quantity: nil},
       %{item: "plate armour", kind: :item, noun: "armour", quantity: nil},
       %{target: "Cobb", kind: :kill}
     ]},
    {"I bought a horse yesterday and I give Brenna my lantern from my pack.", []},
    {"I said I killed Cobb. Maybe I have a sword.", []},
    {"It is noon and I have 50 gold coins, I am wearing my chainmail and I bought a pony.",
     [%{kind: :time, claimed: "noon"}, %{kind: :coins, amount: 50, denomination: "gold"}]}
  ]

  test "the turn's first premise findings, exact strings and order" do
    {:ok, session} = GameSessions.create_session(%{name: "Premise", adventure_id: "tin_valley"})

    for {text, expected} <- @turn_cases do
      assert findings(session, text) == expected, text
    end
  end

  test "claims come out in text order" do
    for {text, expected} <- @claim_cases do
      assert PremiseCheck.claims(text) == expected, text
    end
  end

  @state %{
    inventory: [%{"id" => "hunting_knife", "name" => "hunting knife", "quantity" => 1}],
    coins: %{"gold" => 0, "silver" => 2, "copper" => 0},
    skills: %{},
    people: [%{id: "cobb", name: "Cobb", role: "Rusk's brute"}],
    fronts: [
      %{id: "orc_nest", name: "Orc nest", status: "cleared"},
      %{id: "bandits", name: "Bandit camp", status: nil}
    ],
    combat_wins: 0
  }

  # {text, findings} against @state: a person found by role, a settled
  # front, a front with no status (live), from main
  @state_cases [
    {"I killed the brute.",
     [
       {:kill, "killed the brute",
        "Player claims to have killed the brute; they have won no fight this session and Cobb is alive. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I killed the orc nest.", []},
    {"I killed the bandit camp.",
     [
       {:kill, "killed the bandit camp",
        "Player claims to have killed the bandit camp; they have won no fight this session and Bandit camp is still active. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]},
    {"I killed Rusk's brute and the bandits.",
     [
       {:kill, "killed Rusk's brute",
        "Player claims to have killed Rusk's brute; they have won no fight this session and Cobb is alive. Invent no bounty, reward, token or story that backs the claim. Don't narrate it as true."}
     ]}
  ]

  test "kill subjects: a person, a live front, a settled front" do
    for {text, expected} <- @state_cases do
      found = text |> PremiseCheck.check(@state) |> Enum.map(&{&1.kind, &1.claim, &1.correction})
      assert found == expected, text
    end
  end
end
