# Two-step Jev experiment (offline). Usage: mix run --no-start exp.exs <round> <out.jsonl>
[round, out] = System.argv()
{:ok, _} = Application.ensure_all_started([:req, :jason])
Application.ensure_all_started(:jev)
alias TalesForge.Game.JevIntent
alias TalesForge.IntentEval

key = System.get_env("TYPESAFE_INTENT_PLAYTEST_API_KEY")
if is_nil(key) or key == "", do: raise("no playtest key")
opts = [model: "jev-1.13.0", max_retries: 1, receive_timeout: 15_000, api_key: key]

%{"lines" => lines, "npcs" => npcs} = Jason.decode!(File.read!("/workspace/bobby/exp-two-step-jev/lines.json"))

# --- the current single call (main), as in offerfix-measure ------------------
items = IntentEval.load_items("test/fixtures/intent_eval/items.jsonl")
worlds = IntentEval.load_worlds("test/fixtures/intent_eval/worlds.json")
base = Enum.find(items, &(&1["id"] == "r084"))
stock = %{"innkeep" => [
  %{"id" => "ale_mug", "name" => "Ale", "price_copper" => 2, "quantity" => 72},
  %{"id" => "stew_bowl", "name" => "Bowl of Stew", "price_copper" => 5, "quantity" => 20},
  %{"id" => "bread_cheese", "name" => "Bread and Cheese", "price_copper" => 2, "quantity" => 12}]}
ale_offer = %{"giver" => "innkeep", "giver_name" => "Brenna Holt", "item" => %{"id" => "ale_mug", "name" => "Ale", "quantity" => 1},
  "price" => 2, "options" => [], "location_id" => "valley_inn", "age" => 0}

single = fn line ->
  item = base |> put_in(["context", "stock"], stock) |> put_in(["context", "last_narration"], line["prev"]) |> Map.put("text", line["text"])
  context = IntentEval.build_context(item, worlds)
  offer = if line["offer"], do: ale_offer
  context = if offer, do: Map.put(context, "open_offer", offer), else: context
  cands = JevIntent.candidates(context)
  questions = JevIntent.questions(cands) ++ JevIntent.offer_questions(offer)
  {JevIntent.state(context, line["text"]), questions}
end

# --- step 2: one listener's reading ------------------------------------------
maslow = %{
  "physiological" => "basic needs unmet (hungry, cold, short of sleep or wages)",
  "safety" => "does not feel safe; worried about threats or ruin",
  "belonging" => "safe and fed; cares about friends, guests and community",
  "esteem" => "secure; cares about respect, status and recognition",
  "self_actualisation" => "secure and respected; cares about craft and meaning"}
liking_words = fn l when l >= 0.5 -> "likes the speaker a lot"; l when l >= 0.2 -> "likes the speaker"
  l when l > -0.2 -> "neutral, barely knows the speaker"; l when l > -0.5 -> "dislikes the speaker"; _ -> "dislikes the speaker strongly" end
step2_q = %{
  social_act: %Jev.Choice{
    instructions: "As this listener hears it, what social act is the speaker making toward her?",
    criteria: %{
      request: "Asks her for something: goods, a service, a favour, help.",
      offer: "Offers her something: goods, coin, help, work.",
      accept: "Agrees to something she offered or asked.",
      decline: "Turns down something she offered or asked.",
      insult: "Insults, mocks or belittles her.",
      compliment: "Praises or flatters her.",
      threat: "Threatens or pressures her.",
      apology: "Apologises.",
      joke: "Jokes or teases.",
      question: "Asks her for information: a price, news, directions, advice.",
      unclear: "She cannot tell what the speaker means."
    }
  },
  meaning: %Jev.Choice{
    instructions: "What does she take the speaker to want from her?",
    criteria: %{
      wants_goods: "To buy or get goods, food, drink or a service from her.",
      wants_price: "To know what something costs.",
      accepts_offer: "To take what she just offered.",
      refuses_offer: "To refuse what she just offered.",
      wants_info: "News, gossip, directions or advice.",
      wants_work: "Work or a job.",
      wants_to_sell: "To sell her something.",
      company: "Friendly talk or company.",
      provoke: "To provoke, pressure or mock her.",
      nothing: "Nothing from her (not addressed to her, or just an action).",
      unclear: "She cannot tell."
    }
  },
  tone: %Jev.Choice{
    instructions: "How does the line come across to her, given who she is and how she feels about the speaker?",
    criteria: %{warm: "Warm or pleasant.", neutral: "Neutral, businesslike.", curt: "Curt or tiresome.",
                rude: "Rude or disrespectful.", threatening: "Threatening."}
  }
}
step2_state = fn line, npc ->
  liking = line["liking"][npc["slug"]] || 0.0
  %{
    "task" => "Read the speaker's words as #{npc["name"]} hears them, from her point of view. The speaker is a traveller in her place of work.",
    "listener" => %{
      "name" => npc["name"], "role" => npc["role"], "race" => npc["race"],
      "personality_ocean_1_to_10" => npc["ocean"],
      "maslow_level" => "#{npc["maslow"]}: #{maslow[npc["maslow"]]}",
      "mood" => npc["mood"],
      "concerns" => npc["concerns"],
      "liking_toward_speaker" => "#{Float.round(liking * 1.0, 2)} (#{liking_words.(liking)})",
      "facts_she_knows" => npc["facts"],
      "open_offer" => if(line["offer"], do: "She just answered the speaker: " <> line["offer"], else: "none")
    },
    "what_just_happened" => line["prev"],
    "speaker_says" => line["text"]
  }
end

call = fn state, qs ->
  t0 = System.monotonic_time(:millisecond)
  res = Jev.HTTP.post(state, qs, opts)
  ms = System.monotonic_time(:millisecond) - t0
  case res do
    {:ok, r} ->
      u = Map.get(r, :usage, %{})
      %{ok: true, ms: ms, in: u[:input_tokens], out: u[:output_tokens] || 0, cost: u[:cost],
        bytes: byte_size(Jason.encode!(state)), reply: Map.drop(r, [:usage]) |> Map.take(Enum.map(qs, &elem(&1, 0)) ++ [:confidence, :probabilities])}
    {:error, e} -> %{ok: false, ms: ms, error: inspect(e) |> String.slice(0, 200)}
  end
end


l2_q = %{
  speaker_stance: %Jev.Choice{
    instructions: "Level 2: what does she think the speaker is doing with her likely reaction in mind?",
    criteria: %{
      sincere: "Means it plainly; not playing her.",
      bluffing: "Overstates or pretends, to see how she reacts.",
      lying: "Says something false to get something.",
      haggling: "Pushes the price or terms, expecting her to give way.",
      flirting: "Flirts or charms, hoping she warms to them.",
      testing: "Tests her: her honesty, her prices or her patience.",
      unclear: "She cannot tell."
    }
  }
}
lines = Enum.filter(lines, fn l -> not String.starts_with?(l["text"], ["I look", "I walk", "I stretch"]) end)
npc = npcs["innkeep"]
rows = lines |> Enum.with_index() |> Enum.flat_map(fn {line, i} ->
  st = step2_state.(line, npc)
  a = fn -> c = call.(st, step2_q); Map.merge(c, %{variant: "level1"}) end
  b = fn -> c = call.(st, Map.merge(step2_q, l2_q)); Map.merge(c, %{variant: "level1+field"}) end
  c2 = fn ->
    c1 = call.(st, step2_q)
    r = if c1.ok, do: Map.take(c1.reply, [:social_act, :meaning, :tone]), else: %{}
    st2 = Map.put(st, "her_first_reading", r)
    c = call.(st2, l2_q)
    %{variant: "level1+second_call", ok: c1.ok and c.ok, ms: c1.ms + c.ms, in: c1.in + (c[:in] || 0), cost: c1.cost + (c[:cost] || 0), reply: Map.merge(c1[:reply] || %{}, c[:reply] || %{}), second_ms: c.ms, second_in: c[:in]}
  end
  order = Enum.drop([a, b, c2], rem(i, 3)) ++ Enum.take([a, b, c2], rem(i, 3))
  Enum.map(order, fn f -> f.() |> Map.merge(%{id: line["id"], text: line["text"], round: round}) end)
end)
File.write!(out, Enum.map_join(rows, "\n", &Jason.encode!/1) <> "\n", [:append])
IO.puts("l2 round #{round}: #{Enum.count(rows, & &1.ok)}/#{length(rows)} ok")
