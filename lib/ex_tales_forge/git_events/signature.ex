defmodule TalesForge.GitEvents.Signature do
  @moduledoc """
  Checks GitHub's `X-Hub-Signature-256` header: `sha256=` and the hex
  HMAC-SHA256 of the raw request body, with the webhook secret
  (`GITHUB_WEBHOOK_SECRET`). Pure. The compare takes constant time
  (`Plug.Crypto.secure_compare/2`).
  """

  @doc """
  The header value GitHub sends for `body` with `secret`.

      iex> TalesForge.GitEvents.Signature.sign("s3cret", "{}")
      "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, "s3cret", "{}"), case: :lower)
  """
  @spec sign(String.t(), binary()) :: String.t()
  def sign(secret, body),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)

  @doc """
  True when `header` is the signature of `body` with `secret`. A blank
  secret or a missing header gives false.

      iex> alias TalesForge.GitEvents.Signature
      iex> Signature.valid?("s3cret", "{}", Signature.sign("s3cret", "{}"))
      true
      iex> Signature.valid?("s3cret", "{}", Signature.sign("other", "{}"))
      false
      iex> Signature.valid?("s3cret", "{}", nil)
      false
  """
  @spec valid?(String.t() | nil, binary(), String.t() | nil) :: boolean()
  def valid?(secret, body, header)
      when is_binary(secret) and secret != "" and is_binary(body) and is_binary(header) do
    Plug.Crypto.secure_compare(sign(secret, body), String.downcase(String.trim(header)))
  end

  def valid?(_secret, _body, _header), do: false
end
