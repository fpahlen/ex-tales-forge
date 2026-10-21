defmodule TalesForge.Social.HearingTest do
  use ExUnit.Case, async: true

  alias TalesForge.GameCharacter
  alias TalesForge.Social.{Clarity, Hearing, Listener, Utterance}

  doctest Hearing

  defp hear(voice, ambient_db, distance_m) do
    Hearing.clarity(
      %Utterance{speaker_id: "pc", voice: voice, ambient_db: ambient_db},
      %Listener{character_id: "npc", distance_m: distance_m}
    )
  end

  describe "the worked numbers of design §2.3 (hearing 0)" do
    # {case, voice, ambient dB, distance m, SNR, level, keep}
    @table [
      {"talk to the addressee, quiet inn", :talk, 50, 1.0, 10.0, :clear, 1.0},
      {"talk, bystander 3 m, quiet inn", :talk, 50, 3.0, 0.5, :clear, 1.0},
      {"talk, bystander 3 m, busy inn", :talk, 70, 3.0, -4.5, :partial, 0.8},
      {"whisper, bystander 3 m, quiet inn", :whisper, 50, 3.0, -19.5, :none, 0.0},
      {"whisper to the addressee, quiet inn", :whisper, 50, 0.25, 2.0, :clear, 1.0},
      {"whisper to the addressee, busy inn", :whisper, 70, 0.25, -18.0, :none, 0.0},
      {"shout, 6 m, busy inn", :shout, 70, 6.0, -0.6, :clear, 1.0}
    ]

    for {name, voice, ambient, distance, snr, level, keep} <- @table do
      @tag case: name
      test name do
        clarity = hear(unquote(voice), unquote(ambient), unquote(distance))
        # The design rounds the SNR to one decimal.
        assert_in_delta clarity.snr_db, unquote(snr), 0.05
        assert clarity.level == unquote(level)
        assert_in_delta clarity.keep, unquote(keep), 0.01
      end
    end
  end

  describe "the thresholds of design §2.3" do
    defp at_snr(snr), do: hear(:talk, 50, :math.pow(10, (10 - snr) / 20))

    test "−3 dB is clear, just below is partial at 0.9" do
      assert %Clarity{level: :clear, keep: 1.0} = at_snr(-3.0)
      assert %Clarity{level: :partial, keep: keep} = at_snr(-3.001)
      assert_in_delta keep, 0.9, 0.001
    end

    test "−12 dB is partial at 0.3, below is none" do
      assert %Clarity{level: :partial, keep: keep} = at_snr(-12.0)
      assert_in_delta keep, 0.3, 0.001
      assert %Clarity{level: :none, keep: +0.0} = at_snr(-12.001)
    end

    test "no speech: every listener gets none" do
      assert Hearing.clarity(
               %Utterance{speaker_id: "pc", voice: :none},
               %Listener{character_id: "npc", distance_m: 0.25}
             ) == %Clarity{level: :none, snr_db: nil, keep: 0.0}
    end

    test "the hearing modifier adds to the SNR" do
      base = hear(:talk, 70, 3.0)

      keen =
        Hearing.clarity(
          %Utterance{speaker_id: "pc", voice: :talk, ambient_db: 70},
          %Listener{character_id: "npc", distance_m: 3.0, hearing_db: 4}
        )

      assert_in_delta keen.snr_db - base.snr_db, 4.0, 1.0e-9
    end
  end

  describe "the Lombard rise (design §2.2)" do
    test "talk and shout rise in noise up to a cap; a whisper does not" do
      assert Hearing.voice_db(:talk, 50) == 60
      assert Hearing.voice_db(:talk, 60) == 68
      assert Hearing.voice_db(:talk, 90) == 75
      assert Hearing.voice_db(:shout, 50) == 85
      assert Hearing.voice_db(:shout, 74) == 89
      assert Hearing.voice_db(:shout, 90) == 90
      assert Hearing.voice_db(:whisper, 90) == 40
    end
  end

  describe "property: −6 dB per doubling of distance" do
    test "doubling the distance lowers the SNR by 20·log10(2) ≈ 6.02 dB" do
      state = :rand.seed_s(:exsss, 489)

      Enum.reduce(1..500, state, fn _, state ->
        {d, state} = :rand.uniform_s(state)
        {a, state} = :rand.uniform_s(state)
        {v, state} = :rand.uniform_s(state)
        distance = 0.25 + d * 50
        ambient = 30 + a * 60
        voice = Enum.at([:whisper, :talk, :shout], trunc(v * 3))

        near = hear(voice, ambient, distance)
        far = hear(voice, ambient, 2 * distance)
        assert_in_delta near.snr_db - far.snr_db, 20 * :math.log10(2), 1.0e-9
        state
      end)
    end

    test "under 0.25 m counts as 0.25 m" do
      assert hear(:whisper, 50, 0.1).snr_db == hear(:whisper, 50, 0.25).snr_db
    end
  end

  describe "modifier/1 (design §2.4)" do
    test "race: elf +3, half-elf +1, others 0" do
      assert Hearing.modifier(%GameCharacter{race: "elf"}) == 3
      assert Hearing.modifier(%GameCharacter{race: "half_elf"}) == 1
      assert Hearing.modifier(%GameCharacter{race: "human"}) == 0
      assert Hearing.modifier(%GameCharacter{race: "dwarf"}) == 0
    end

    test "perception level / 25 rounded down, 0..+4; no perception adds 0" do
      assert Hearing.modifier(%GameCharacter{race: "human", skills: %{"perception" => 24}}) == 0
      assert Hearing.modifier(%GameCharacter{race: "human", skills: %{"perception" => 25}}) == 1
      assert Hearing.modifier(%GameCharacter{race: "human", skills: %{"perception" => 99}}) == 3
      assert Hearing.modifier(%GameCharacter{race: "human", skills: %{"perception" => 100}}) == 4
      assert Hearing.modifier(%GameCharacter{race: "elf", skills: %{"insight" => 80}}) == 3
      assert Hearing.modifier(%GameCharacter{race: nil, skills: nil}) == 0
    end
  end

  describe "fragment/3 (design §2.6)" do
    @line "Brenna, I said I would take the ale and pay you tomorrow at dawn"

    test "the same seed gives the same fragment" do
      partial = %Clarity{level: :partial, keep: 0.6}
      seed = Hearing.seed("session-1", 4, "innkeep")

      assert Hearing.fragment(@line, partial, seed) == Hearing.fragment(@line, partial, seed)
      assert seed == Hearing.seed("session-1", 4, "innkeep")
    end

    test "a partial fragment keeps words in order and marks each dropped run once" do
      fragment = Hearing.fragment(@line, %Clarity{level: :partial, keep: 0.6}, 42)
      words = String.split(fragment)

      assert "…" in words
      refute fragment =~ "… …"
      kept = Enum.reject(words, &(&1 == "…"))
      assert kept == Enum.filter(String.split(@line), &(&1 in kept))
    end

    test "clear keeps every word; none keeps none" do
      assert Hearing.fragment(@line, %Clarity{level: :clear, keep: 1.0}, 1) == @line
      assert Hearing.fragment(@line, %Clarity{level: :none, keep: 0.0}, 1) == "…"
    end
  end
end
