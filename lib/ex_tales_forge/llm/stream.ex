defmodule TalesForge.LLM.Stream do
  @moduledoc """
  Reads a streamed chat completion (`stream: true`, server-sent events).

  `events/1` splits the received bytes into SSE `data:` payloads. It keeps an
  incomplete event for the next chunk.

  `partial_narrative/1` reads the `narrative` string from the start of a JSON
  reply that is not complete yet. The strict narration schema puts `narrative`
  first, so the model writes it first. The function decodes the JSON string
  escapes. It stops before an escape that is not complete, so the text grows
  and never shows a broken character.
  """

  @doc """
  Splits `buffer` into complete SSE `data:` payloads and the rest.

      iex> TalesForge.LLM.Stream.events("data: {\\"a\\":1}\\n\\ndata: [DONE]\\n\\ndata: {")
      {[~s({"a":1}), "[DONE]"], "data: {"}
  """
  @spec events(binary()) :: {[binary()], binary()}
  def events(buffer) do
    parts = buffer |> String.replace("\r\n", "\n") |> String.split("\n\n")
    {complete, [rest]} = Enum.split(parts, -1)

    payloads =
      complete
      |> Enum.flat_map(&String.split(&1, "\n"))
      |> Enum.flat_map(fn
        "data:" <> payload -> [String.trim(payload)]
        _other -> []
      end)
      |> Enum.reject(&(&1 == ""))

    {payloads, rest}
  end

  @doc """
  Reads one SSE payload: the content delta (`choices[0].delta.content`, or
  "") and the usage map (or nil). `:done` for the end marker.
  """
  @spec decode_event(binary()) :: {String.t(), map() | nil} | :done
  def decode_event("[DONE]"), do: :done

  def decode_event(payload) do
    case Jason.decode(payload) do
      {:ok, %{} = event} ->
        text =
          case event["choices"] do
            [%{"delta" => %{"content" => text}} | _] when is_binary(text) -> text
            _ -> ""
          end

        usage = if is_map(event["usage"]), do: event["usage"]
        {text, usage}

      _ ->
        {"", nil}
    end
  end

  @doc ~S"""
  The `narrative` text so far in a partial JSON reply, or nil when the reply
  does not start with the `narrative` key yet.

      iex> TalesForge.LLM.Stream.partial_narrative(~s({"narrative":"The lamp \\"gut))
      ~s(The lamp "gut)
      iex> TalesForge.LLM.Stream.partial_narrative(~s({"narrative":"Line\\nNext","gm))
      "Line\nNext"
      iex> TalesForge.LLM.Stream.partial_narrative(~s({"narrative":"caf\\u00e))
      "caf"
      iex> TalesForge.LLM.Stream.partial_narrative(~s({"narr))
      nil
  """
  @spec partial_narrative(binary()) :: String.t() | nil
  def partial_narrative(content) do
    case Regex.run(~r/\A\s*(?:```(?:json)?\s*)?\{\s*"narrative"\s*:\s*"/, content, return: :index) do
      [{0, len}] -> content |> binary_part(len, byte_size(content) - len) |> read_string([])
      _ -> nil
    end
  end

  defp read_string(<<?", _::binary>>, acc), do: finish(acc)

  defp read_string(<<?\\, ?u, a, b, c, d, rest::binary>>, acc),
    do: unicode(<<a, b, c, d>>, rest, acc)

  defp read_string(<<?\\, ?u, _::binary>>, acc), do: finish(acc)
  defp read_string(<<?\\, e, rest::binary>>, acc), do: read_string(rest, [escape(e) | acc])
  defp read_string(<<?\\>>, acc), do: finish(acc)
  defp read_string(<<>>, acc), do: finish(acc)

  defp read_string(<<c::utf8, rest::binary>>, acc), do: read_string(rest, [<<c::utf8>> | acc])
  # An incomplete UTF-8 sequence at the end of the chunk: wait for more bytes.
  defp read_string(_partial, acc), do: finish(acc)

  defp unicode(hex, rest, acc) do
    case Integer.parse(hex, 16) do
      {hi, ""} when hi in 0xD800..0xDBFF -> surrogate_pair(hi, rest, acc)
      {cp, ""} when cp in 0xDC00..0xDFFF -> read_string(rest, acc)
      {cp, ""} -> read_string(rest, [<<cp::utf8>> | acc])
      _ -> finish(acc)
    end
  end

  defp surrogate_pair(hi, <<?\\, ?u, a, b, c, d, rest::binary>>, acc) do
    case Integer.parse(<<a, b, c, d>>, 16) do
      {lo, ""} when lo in 0xDC00..0xDFFF ->
        cp = 0x10000 + Bitwise.bsl(hi - 0xD800, 10) + (lo - 0xDC00)
        read_string(rest, [<<cp::utf8>> | acc])

      _ ->
        read_string(rest, acc)
    end
  end

  # The low half has not arrived yet.
  defp surrogate_pair(_hi, _rest, acc), do: finish(acc)

  defp escape(?n), do: "\n"
  defp escape(?t), do: "\t"
  defp escape(?r), do: "\r"
  defp escape(?b), do: "\b"
  defp escape(?f), do: "\f"
  defp escape(c), do: <<c>>

  defp finish(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
end
