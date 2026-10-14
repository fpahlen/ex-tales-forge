defmodule TalesForgeWeb.WorkLogApiControllerTest do
  use TalesForgeWeb.ConnCase, async: false

  setup do
    Application.put_env(:ex_tales_forge, :board_bots,
      case: [api_token: "case-token"],
      bobby: [],
      gentry: []
    )

    on_exit(fn -> Application.delete_env(:ex_tales_forge, :board_bots) end)
    :ok
  end

  defp conn_for(token) do
    if token,
      do: put_req_header(build_conn(), "authorization", "Bearer " <> token),
      else: build_conn()
  end

  defp add(body), do: post(conn_for("case-token"), ~p"/internal/work-log/entries", body)

  @entry %{
    "founder" => "Fredrik@Example.com",
    "date" => "2026-01-12",
    "hours" => 2.5,
    "reason" => "Planning"
  }

  test "401 without a bot token" do
    assert get(conn_for(nil), ~p"/internal/work-log/entries").status == 401
    assert get(conn_for("wrong"), ~p"/internal/work-log/entries").status == 401
    assert post(conn_for(nil), ~p"/internal/work-log/entries", @entry).status == 401
  end

  test "a bot adds an entry, a duplicate is skipped, and GET lists it" do
    assert %{"result" => "ok", "entry" => %{"added_by" => "bot:case", "hours" => 2.5}} =
             json_response(add(@entry), 201)

    assert %{"result" => "skipped"} = json_response(add(@entry), 200)

    assert %{"result" => "ok"} = json_response(add(%{@entry | "date" => "2026-01-13"}), 201)

    assert %{"entries" => [first, _second]} =
             json_response(get(conn_for("case-token"), ~p"/internal/work-log/entries"), 200)

    assert first["founder"] == "fredrik@example.com"
    assert first["date"] == "2026-01-12"

    assert %{"entries" => [_]} =
             json_response(
               get(conn_for("case-token"), ~p"/internal/work-log/entries?from=2026-01-13"),
               200
             )
  end

  test "a bad body gives 422" do
    assert %{"errors" => %{"hours" => _}} = json_response(add(%{@entry | "hours" => 0}), 422)
    assert json_response(add(%{"reason" => "x"}), 422)["errors"]["founder"]
  end
end
