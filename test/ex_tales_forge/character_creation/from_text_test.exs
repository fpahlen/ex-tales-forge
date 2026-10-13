defmodule TalesForge.CharacterCreation.FromTextTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterCreation.FromText
  alias TalesForge.CharacterTextStub, as: Stub
  alias TalesForge.Schemas.AICall

  @adventure "tin_valley"
  @text "Mira is an elf ranger from the deep woods. She hunted deer for her village."

  defp draft, do: CC.new(@adventure, seed_key: "text-1")

  defp read_build(reply) do
    Stub.put(reply)
    {:ok, reading} = FromText.read(@adventure, @text)
    {:ok, d} = FromText.build(draft(), reading)
    {reading, d}
  end

  test "a clear description gives labels with high confidence and no questions" do
    {reading, d} = read_build(Stub.reply())

    assert reading.questions == []
    assert reading.labels["race"] == %{value: "elf", confidence: 0.9}
    assert d.model == "from_text"
    assert {d.race, d.class, d.occupation, d.name} == {"elf", "ranger", "hunter", "Mira Vale"}
    assert d.base_stats["DEX"] == 16
    assert d.approved == false
  end

  test "the draft fills through the normal functions and needs approval before finalize" do
    {_reading, d} = read_build(Stub.reply())

    assert {:error, errors} = CC.validate(d)
    assert errors == [approval: "approve the AI draft before play"]
    assert {:error, _} = CC.finalize(d)

    {:ok, d} = CC.approve(d)
    assert CC.validate(d) == :ok
    assert {:ok, c} = CC.finalize(d)
    assert c["creation"]["model"] == "from_text"
  end

  test "labels with low confidence keep the rules defaults" do
    {_reading, d} = read_build(Stub.reply(%{}, 0.2))
    plain = draft()

    assert {d.race, d.class, d.occupation, d.name} ==
             {plain.race, plain.class, plain.occupation, ""}

    assert d.base_stats == plain.base_stats
  end

  test "unknown values get confidence 0" do
    reply = Stub.reply(%{"race" => %{"value" => "dragon", "confidence" => 1.0}})
    {reading, d} = read_build(reply)

    assert reading.labels["race"].confidence == 0.0
    assert d.race == "human"
  end

  test "stats over the budget and the range fit the point-buy rules" do
    stats = for s <- ~w(STR DEX CON INT WIS CHA), do: %{"stat" => s, "value" => 20}
    {_reading, d} = read_build(Stub.reply(%{"stats" => stats}))
    {:ok, d} = CC.approve(d)

    assert CC.points_spent(d) <= 75
    assert Enum.all?(Map.values(CC.final_stats(d)), &(&1 in 3..18))
    assert CC.validate(d) == :ok
  end

  test "skills the rules refuse give the suggested spread" do
    skills =
      for s <- ~w(stealth survival tracking melee_combat), do: %{"skill" => s, "level" => 7}

    {_reading, d} = read_build(Stub.reply(%{"skills" => skills, "skills_confidence" => 0.9}))
    {:ok, d} = CC.approve(d)

    assert CC.validate(d) == :ok
  end

  test "the AI asks at most 2 questions, and the answers give no more questions" do
    qs = ["Which people?", "Which work?", "Which name?"]
    Stub.put(Stub.reply(%{"questions" => qs}, 0.3))

    {:ok, first} = FromText.read(@adventure, @text)
    assert first.questions == ["Which people?", "Which work?"]

    {:ok, second} = FromText.read(@adventure, @text, [{"Which people?", "Elf"}])
    assert second.questions == []
    assert_received {:character_text_call, _}
    assert_received {:character_text_call, user}
    assert user =~ "A: Elf"
  end

  test "an empty description makes no AI call" do
    Stub.put(Stub.reply())
    assert FromText.read(@adventure, "   ") == {:error, :empty}
    refute_received {:character_text_call, _}
  end

  test "an AI error comes back as an error" do
    Stub.put(fn _s, _u -> {:error, :timeout} end)
    assert FromText.read(@adventure, @text) == {:error, :timeout}
  end

  test "the default adapter calls the mock LLM and writes one ai_calls row" do
    Stub.reset()
    assert {:ok, reading} = FromText.read(@adventure, @text)
    assert reading.questions == []

    assert [%AICall{purpose: "character_text", call_type: "llm", status: "ok"}] =
             Repo.all(AICall)
  end

  test "approve is for the description model only" do
    assert {:error, {:approval, _}} = CC.approve(draft())
  end
end
