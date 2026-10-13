defmodule TalesForgeWeb.GitHubWebhookControllerTest do
  @moduledoc "POST /webhooks/github: signature check, broadcast on \"github\", 204 for other events."
  use TalesForgeWeb.ConnCase, async: false

  alias TalesForge.GitEvents.GitEvent
  alias TalesForge.GitEvents.Signature

  @secret "test-webhook-secret"
  @body ~s({"ref":"refs/heads/main","after":"abc1234","repository":{"full_name":"o/r"},"commits":[{"id":"abc1234"}]})

  setup do
    Application.put_env(:ex_tales_forge, :github_webhook_secret, @secret)
    on_exit(fn -> Application.delete_env(:ex_tales_forge, :github_webhook_secret) end)
    TalesForge.GitEvents.subscribe()
    :ok
  end

  defp deliver(conn, event, body, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-hub-signature-256", signature)
    |> post("/webhooks/github", body)
  end

  test "a valid signature broadcasts the event and answers 202", %{conn: conn} do
    conn = deliver(conn, "push", @body, Signature.sign(@secret, @body))
    assert conn.status == 202
    assert_receive {:git_event, %GitEvent{type: :push, repo: "o/r", sha: "abc1234"}}
  end

  test "an invalid signature answers 401 and broadcasts nothing", %{conn: conn} do
    conn = deliver(conn, "push", @body, Signature.sign("wrong", @body))
    assert conn.status == 401
    refute_receive {:git_event, _}, 50
  end

  test "an unknown event answers 204", %{conn: conn} do
    body = ~s({"zen":"x","repository":{"full_name":"o/r"}})
    conn = deliver(conn, "ping", body, Signature.sign(@secret, body))
    assert conn.status == 204
    refute_receive {:git_event, _}, 50
  end

  test "without the secret the endpoint answers 404", %{conn: conn} do
    Application.delete_env(:ex_tales_forge, :github_webhook_secret)
    conn = deliver(conn, "push", @body, Signature.sign(@secret, @body))
    assert conn.status == 404
  end
end
