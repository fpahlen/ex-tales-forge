defmodule Workflow.Push.Http do
  @moduledoc """
  Sends one web push request (`WebPushEx.Request`) to the push service with
  Req. Gives the HTTP status, or the error.
  """

  @doc "Posts `request` to its endpoint. The timeout is 15 s."
  @spec post(WebPushEx.Request.t()) :: {:ok, pos_integer()} | {:error, term()}
  def post(%WebPushEx.Request{} = request) do
    case Req.post(URI.to_string(request.endpoint),
           body: request.body,
           headers: request.headers,
           retry: false,
           receive_timeout: 15_000
         ) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end
end
