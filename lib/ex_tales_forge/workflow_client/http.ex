defmodule TalesForge.WorkflowClient.Http do
  @moduledoc """
  The HTTP adapter of `TalesForge.WorkflowClient`. It posts the turn event
  to `POST /internal/workflow/work-log/turns`
  (`TalesForgeWeb.WorkflowWorkLogController`).

  - Base URL: config `:ex_tales_forge, :workflow_client, base_url:`.
  - Token: the secret `WORKFLOW_API_TOKEN` as a bearer token (config
    `:ex_tales_forge, :workflow_api, token:`).
  - 5 s timeout and no retries in the request. The Oban job retries.
  """

  @behaviour TalesForge.WorkflowClient.Adapter

  @path "/internal/workflow/work-log/turns"
  @timeout_ms 5_000

  @impl TalesForge.WorkflowClient.Adapter
  def push_turn(event) do
    with {:url, url} when is_binary(url) <- {:url, base_url()},
         {:token, token} when is_binary(token) <- {:token, token()} do
      post(String.trim_trailing(url, "/") <> @path, event, token)
    else
      {:url, _} -> {:error, :no_base_url}
      {:token, _} -> {:error, :no_token}
    end
  end

  defp post(url, event, token) do
    case Req.post(
           [
             url: url,
             json: event,
             auth: {:bearer, token},
             receive_timeout: @timeout_ms,
             connect_options: [timeout: @timeout_ms],
             retry: false,
             redirect: false
           ] ++ Application.get_env(:ex_tales_forge, :workflow_client_req_options, [])
         ) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp base_url,
    do: Application.get_env(:ex_tales_forge, :workflow_client, [])[:base_url]

  defp token do
    case Application.get_env(:ex_tales_forge, :workflow_api, [])[:token] do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end
end
