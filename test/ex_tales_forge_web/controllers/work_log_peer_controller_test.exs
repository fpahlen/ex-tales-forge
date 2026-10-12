defmodule TalesForgeWeb.WorkLogPeerControllerTest do
  use TalesForgeWeb.ConnCase, async: false

  alias TalesForge.WorkLog

  setup do
    on_exit(fn ->
      Application.delete_env(:ex_tales_forge, :costs_peer)
      Application.delete_env(:ex_tales_forge, :app_name)
    end)

    :ok
  end

  defp get_events(header, since \\ "2026-01-01T00:00:00Z") do
    build_conn()
    |> then(&if(header, do: put_req_header(&1, "authorization", header), else: &1))
    |> get(~p"/internal/work-log/events?#{[since: since]}")
  end

  test "404 on production and while the token is unset" do
    assert get_events("Bearer x").status == 404
    Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
    assert get_events("Bearer x").status == 404
  end

  test "on playtest: 401 without the right token, the events with it" do
    Application.put_env(:ex_tales_forge, :app_name, "tales-forge-playtest")
    Application.put_env(:ex_tales_forge, :costs_peer, token: "right")
    {:ok, _} = WorkLog.record("ada@example.com", "turn", "t1")

    assert get_events(nil).status == 401
    assert get_events("Bearer wrong").status == 401

    assert %{"events" => [%{"founder" => "ada@example.com", "kind" => "turn", "ref" => "t1"}]} =
             json_response(get_events("Bearer right"), 200)

    assert get_events("Bearer right", "yesterday").status == 400
  end
end
