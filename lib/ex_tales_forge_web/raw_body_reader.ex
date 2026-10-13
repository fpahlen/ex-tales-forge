defmodule TalesForgeWeb.RawBodyReader do
  @moduledoc """
  The body reader of `Plug.Parsers` (`TalesForgeWeb.Endpoint`). For the
  GitHub webhook path (`#{"/webhooks/github"}`) it keeps the raw body in
  `conn.assigns.raw_body`, because the signature is over the exact bytes.
  Other paths read the body as usual.
  """

  @path "/webhooks/github"

  @doc "Reads the body like `Plug.Conn.read_body/2` and keeps it on the webhook path."
  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(%Plug.Conn{request_path: @path} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, body, conn} when status in [:ok, :more] -> {status, body, keep(conn, body)}
      other -> other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp keep(conn, body),
    do: Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
end
