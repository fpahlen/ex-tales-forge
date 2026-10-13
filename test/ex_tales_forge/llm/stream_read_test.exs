defmodule TalesForge.LLM.StreamReadTest do
  @moduledoc "partial_narrative/1 takes plain text in one split and keeps the escape rules."
  use ExUnit.Case, async: true

  alias TalesForge.LLM.Stream

  defp narrative(json), do: Stream.partial_narrative(~s({"narrative":") <> json)

  test "reads long plain text, escapes and the closing quote" do
    text = String.duplicate("Die Laterne flackert. ", 500)
    assert narrative(text <> ~S(\"Hallo\"\nEnde", "gm":1})) == text <> ~s("Hallo"\nEnde)
  end

  test "keeps multi-byte characters and stops before an incomplete one" do
    assert narrative("Käse und Brot") == "Käse und Brot"
    <<first, _rest::binary>> = "ä"
    assert narrative("Kä" <> <<first>>) == "Kä"
  end

  test "stops at bytes that are not UTF-8 and keeps the text before them" do
    assert narrative("ok" <> <<0xFF>> <> "more") == "ok"
  end

  test "reads surrogate pairs and stops at an incomplete escape" do
    assert narrative(~S(a\ud83d\ude00b)) == "a😀b"
    assert narrative(~S(a\u00)) == "a"
    assert narrative("a\\") == "a"
  end
end
