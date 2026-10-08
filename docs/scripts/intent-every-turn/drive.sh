#!/bin/bash
# Round-robin driver for the INTENT_CALL_EVERY_TURN off/on batch (from /workspace/compare/drive.sh):
# for each round r, for each persona, start the Series with that one persona and
# runs: r, so it plays exactly that persona's r-th run; wait until it is done.
# A run that does not count as done is logged and the loop continues; the last pass of round 2 tops it up.
# Stop early: touch /workspace/intent-every/STOP. Resume: run this script again (done runs are skipped).
export PATH=$HOME/.fly/bin:$PATH
APP=tales-forge-playtest; M=801e9ef6136178; S=${SERIES:?set SERIES}
PERSONAS="paul lotta lars ronny hawk"; ROUND_LIST=${ROUND_LIST:-"1 2 2"}
rpc() { for i in 1 2 3 4 5; do out=$(timeout 90 flyctl machine exec $M -a $APP "/app/bin/ex_tales_forge rpc '$1'" 2>&1) && { echo "$out"; return 0; }; sleep 20; done; echo "RPC_FAIL $out"; return 1; }
done_n() { rpc "IO.puts(Map.get(TalesForge.Playtest.Series.done_counts(\"$S\"), {\"$1\", \"default\"}, 0))" | tail -1; }
log() { echo "$(date '+%F %T') $*"; }
for r in $ROUND_LIST; do
  for p in $PERSONAS; do
    [ -f /workspace/intent-every/STOP ] && { log "STOP file, stopping"; exit 0; }
    n=$(done_n $p); [[ "$n" =~ ^[0-9]+$ ]] || { log "cannot read progress: $n"; exit 2; }
    [ "$n" -ge "$r" ] && continue
    tl=10; [ $p = hawk ] && tl=12
    log "round $r: $p (turn_limit $tl)"
    res=$(rpc "IO.inspect(TalesForge.Playtest.Series.start(\"$S\", personas: [\"$p\"], variants: [\"default\"], runs: $r, turn_limit: $tl))" | grep -v "\[info\]" | tr -d '\n')
    log "start -> $res"
    [[ "$res" =~ \{:ok,\ [0-9]+\} || "$res" == *":already_running"* ]] || { log "unexpected start result, stopping"; exit 3; }
    sleep 60
    while true; do
      pl=$(rpc "IO.puts(TalesForge.Playtest.Series.playing?())" | tail -1)
      [ "$pl" = "false" ] && break
      [[ "$pl" == "true" ]] || log "poll: $pl"
      sleep 45
    done
    last=$(rpc "import Ecto.Query; r = TalesForge.Repo.one(from r in TalesForge.Schemas.PlaytestRun, where: r.persona == \"$p\" and like(r.notes, \"series=$S %\"), order_by: [desc: r.started_at], limit: 1); IO.puts(\"run=#{r.id} status=#{r.status} stop=#{r.stop_reason} turns=#{r.turns_played} persona_cost=#{r.persona_cost_micro_usd} game_cost=#{TalesForge.AICalls.total_cost_for_session(r.game_session_id)}\")" | tail -1)
    log "finished: $p $last"
    n=$(done_n $p)
    [ "$n" -ge "$r" ] || log "NOT DONE (hang/timeout?): $p $last -- continuing"
  done
done
log "series complete"
