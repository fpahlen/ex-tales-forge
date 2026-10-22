defmodule TalesForge.Game.TextHelpersCharacterizationTest do
  @moduledoc """
  Characterization of `Gestures.Forms.verb/1`, `DialogueMemory.lines/2` and
  `Rest.rest_place?/2` before round 2 PR 10: exact outputs from main,
  except that "ee" verbs now keep the "ee" before -ing ("seeing", not the
  old "seing"). Pure, no LLM calls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.{DialogueMemory, Rest}
  alias TalesForge.Game.Gestures.Forms

  @verbs [
    {"beg", ["beg", "begs", "begging", "begged"]},
    {"bless", ["bless", "blesses", "blessing", "blessed"]},
    {"dab", ["dab", "dabs", "dabbing", "dabbed"]},
    {"drum", ["drum", "drums", "drumming", "drummed"]},
    {"fix", ["fix", "fixes", "fixing", "fixed"]},
    {"free", ["free", "frees", "freeing", "freed"]},
    {"glance", ["glance", "glances", "glancing", "glanced"]},
    {"grin", ["grin", "grins", "grinning", "grinned"]},
    {"hug", ["hug", "hugs", "hugging", "hugged"]},
    {"hum", ["hum", "hums", "humming", "hummed"]},
    {"kiss", ["kiss", "kisses", "kissing", "kissed"]},
    {"lean", ["lean", "leans", "leaning", "leaned"]},
    {"nod", ["nod", "nods", "nodding", "nodded"]},
    {"open", ["open", "opens", "opening", "opened"]},
    {"pat", ["pat", "pats", "patting", "patted"]},
    {"pour", ["pour", "pours", "pouring", "poured"]},
    {"rub", ["rub", "rubs", "rubbing", "rubbed"]},
    {"scratch", ["scratch", "scratches", "scratching", "scratched"]},
    {"see", ["see", "sees", "seeing", "seed"]},
    {"shrug", ["shrug", "shrugs", "shrugging", "shrugged"]},
    {"sit", ["sit", "sits", "sitting", "sitted"]},
    {"stop", ["stop", "stops", "stopping", "stopped"]},
    {"tap", ["tap", "taps", "tapping", "tapped"]},
    {"wash", ["wash", "washes", "washing", "washed"]},
    {"wipe", ["wipe", "wipes", "wiping", "wiped"]},
    {"flee", ["flee", "flees", "fleeing", "fleed"]},
    {"agree", ["agree", "agrees", "agreeing", "agreed"]},
    {"make", ["make", "makes", "making", "maked"]},
    {"hoe", ["hoe", "hoes", "hoeing", "hoed"]}
  ]

  test "verb forms of 29 verbs" do
    for {base, forms} <- @verbs, do: assert(Forms.verb(base) == forms, base)
  end

  @npcs [%{id: "innkeep", names: ["Brenna Holt", "Brenna"]}, %{id: "rusk", names: ["Rusk"]}]

  # {prose, npcs, lines}
  @lines [
    {"Brenna wipes a mug. \"We close at midnight.\" Rusk laughs: \"Not for me.\"", @npcs,
     [{"innkeep", "We close at midnight."}, {"rusk", "Not for me."}]},
    {"\"Leave,\" says Rusk. \"Now.\" Brenna sighs.", @npcs,
     [{"rusk", "Leave,"}, {"rusk", "Now."}]},
    {"\"Hello there.\" The fire pops. “Welcome, traveller,” Brenna says, and Rusk nods.", @npcs,
     [{"innkeep", "Welcome, traveller,"}]},
    {"Rusk glances at Brenna. \"Pay up.\"", @npcs, [{"innkeep", "Pay up."}]},
    {"\"Hm.\" \"Fine,\" she says.", [%{id: "innkeep", names: ["Brenna"]}],
     [{"innkeep", "Hm."}, {"innkeep", "Fine,"}]},
    {"\"Nobody knows who said this.\"", @npcs, []},
    {"Brenna Holt says \"a\" and \"ok then\"", @npcs, [{"innkeep", "and"}]},
    {"No quotes here.", @npcs, []},
    {"\"Hi\"", [], []},
    {nil, @npcs, []}
  ]

  test "quoted lines and their speakers, in order" do
    for {prose, npcs, expected} <- @lines,
        do: assert(DialogueMemory.lines(prose, npcs) == expected, inspect(prose))
  end

  @world %{
    "locations" => %{
      "inn_yard" => %{"name" => "Yard"},
      "camp" => %{"fixtures" => ["bedroll"]},
      "cot_room" => %{"fixtures" => "two cots"},
      "pilgrim" => %{
        "name" => "The Weary Pilgrim",
        "blurb" => "A low-ceilinged tavern smelling of woodsmoke."
      },
      "square" => %{
        "name" => "Crossroads Square",
        "blurb" => "Mud and cobbles. The inn is nearby.",
        "fixtures" => ["signpost"]
      },
      "hall" => %{"name" => "Hall", "aliases" => ["the guest house"]},
      "barn" => %{"name" => "Barn", "aliases" => "the bunkhouse"},
      "shop" => %{"name" => nil, "blurb" => 7}
    }
  }

  # {location id, rest place?}: by id, name, aliases, blurb or fixtures; the
  # last three are not in the world and come from the pack (or nowhere).
  @places [
    {"inn_yard", true},
    {"camp", true},
    {"cot_room", true},
    {"pilgrim", true},
    {"square", false},
    {"hall", true},
    {"barn", true},
    {"shop", false},
    {"valley_inn", true},
    {"market_square", false},
    {"nowhere", false}
  ]

  test "rest places" do
    for {id, expected} <- @places, do: assert(Rest.rest_place?(@world, id) == expected, id)
    assert Rest.rest_place?(%{}, "valley_inn")
    refute Rest.rest_place?(%{}, nil)
    refute Rest.rest_place?(nil, "valley_inn")
  end
end
