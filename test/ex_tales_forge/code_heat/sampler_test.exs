defmodule TalesForge.CodeHeat.SamplerTest do
  use TalesForge.DataCase, async: false

  import Ecto.Query

  alias TalesForge.CodeHeat
  alias TalesForge.CodeHeat.Sampler
  alias TalesForge.CodeHeat.Tracer
  alias TalesForge.Schemas.CodeHeatSnapshot

  defmodule Target do
    @moduledoc false
    def work(x), do: x + 1
  end

  setup do
    on_exit(fn -> Application.delete_env(:ex_tales_forge, CodeHeat) end)
  end

  test "the sampler does not start when the heat map is off" do
    assert Sampler.start_link(name: :code_heat_off) == :ignore
  end

  test "the tracer counts calls and stops cleanly" do
    {:ok, session} = Tracer.start([Target])
    Enum.each(1..100, &Target.work/1)

    assert [{Target, :work, 1, 100, time_us}] =
             session
             |> Tracer.read([Target, NoSuchModule])
             |> Enum.filter(&(elem(&1, 1) == :work))

    assert time_us >= 0
    assert :ok = Tracer.stop(session)
    assert :ok = Tracer.stop(session)
  end

  test "the sampler writes one sample each hour with the counts of that hour" do
    pid = start_supervised!({Sampler, name: :code_heat_test, modules: [Target], force: true})
    Ecto.Adapters.SQL.Sandbox.allow(TalesForge.Repo, self(), pid)

    Enum.each(1..5, &Target.work/1)
    send(pid, :read)
    send(pid, :other)
    _ = :sys.get_state(pid)

    assert [first] = Repo.all(CodeHeatSnapshot)
    assert [%{"function" => "work/1", "calls" => 5}] = first.rows
    assert first.modules == 1

    Enum.each(1..3, &Target.work/1)
    send(pid, :read)
    _ = :sys.get_state(pid)

    assert [_, second] = Repo.all(from(s in CodeHeatSnapshot, order_by: s.ended_at))
    assert [%{"function" => "work/1", "calls" => 3}] = second.rows
    assert DateTime.compare(second.started_at, first.ended_at) == :eq

    Enum.each(1..2, &Target.work/1)
    assert {:ok, snapshot} = Sampler.sample_now(:code_heat_test)
    assert [%{"calls" => 2}] = snapshot.rows

    stop_supervised!(Sampler)
  end

  test "the sampler writes the current counts when it stops" do
    pid = start_supervised!({Sampler, name: :code_heat_stop, modules: [Target], force: true})
    Ecto.Adapters.SQL.Sandbox.allow(TalesForge.Repo, self(), pid)

    Enum.each(1..7, &Target.work/1)
    assert Repo.all(CodeHeatSnapshot) == []

    :ok = stop_supervised(Sampler)

    assert [snapshot] = Repo.all(CodeHeatSnapshot)
    assert [%{"function" => "work/1", "calls" => 7}] = snapshot.rows
  end
end
