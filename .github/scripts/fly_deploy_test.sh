#!/usr/bin/env bash
# Tests .github/scripts/fly_deploy.sh with a fake flyctl on PATH. No Fly
# access. The failing outputs are cut from whyse-ab/workflow Deploy runs
# 39043783216 (release machine) and 39150156882 (green machine), with the
# app renamed. CI runs it (ci.yml, Test job). Run: .github/scripts/fly_deploy_test.sh
set -uo pipefail

script=$(cd "$(dirname "$0")" && pwd)/fly_deploy.sh
image=registry.fly.io/tales-forge:deployment-01M581R1RMZHJ07TP8JR9M5JYP
build="==> Building image
image: $image
image size: 127 MB"
release_ok="> Created release_command machine 080776dae27328
> Machine 080776dae27328 has state: stopped
✔ release_command 080776dae27328 completed successfully"

green_stuck="$build
$release_ok
Updating existing machines in 'tales-forge' with bluegreen strategy
Creating green machines
  Created machine 8e2d9db7396368 [app]
Waiting for all green machines to start
  Machine 8e2d9db7396368 [app] - created
Rolling back failed deployment
  Deleted machine 8e2d9db7396368 [app]
Error: wait timeout
could not get all green machines into started state"

release_stuck="$build
> Created release_command machine 85e767b4199638
> Waiting for 85e767b4199638 to have state: stopped
✖ Failed: error running release_command machine: timeout reached waiting for machine's state to change
Error: release command failed - aborting deployment. error running release_command machine: timeout reached waiting for machine's state to change"

long_migration="$build
> Created release_command machine 85e767b4199638
> Machine 85e767b4199638 has state: stopped
> Machine 85e767b4199638 has state: started
✖ Failed: error running release_command machine: timeout reached waiting for machine's state to change"

unhealthy="$build
$release_ok
  Machine 8e2d9db7396368 [app] - started
Error: could not get all green machines to be healthy"

build_failed="==> Building image
Error: failed to fetch an image or build from source: error building: exit code: 1"

ok="$build
$release_ok
✔ Machine 8e2d9db7396368 [app] update finished: success"

# run NAME WANT_EXIT WANT_DEPLOYS OUTPUT... : one OUTPUT per flyctl deploy
# call, as "EXIT:TEXT". CONFIG, if set, is passed on to the script.
fails=0
run() {
  local name=$1 want_exit=$2 want_deploys=$3
  shift 3
  local dir
  dir=$(mktemp -d)
  local i=1
  for out in "$@"; do
    printf '%s\n' "${out#*:}" > "$dir/out.$i"
    printf '%s\n' "${out%%:*}" > "$dir/exit.$i"
    i=$((i + 1))
  done
  cat > "$dir/flyctl" <<'FAKE'
#!/usr/bin/env bash
dir=$(dirname "$0")
echo "flyctl $*" >> "$dir/calls"
[ "$1" = deploy ] || exit 0
n=$(($(cat "$dir/n" 2>/dev/null || echo 0) + 1))
echo "$n" > "$dir/n"
cat "$dir/out.$n"
exit "$(cat "$dir/exit.$n")"
FAKE
  chmod +x "$dir/flyctl"
  PATH="$dir:$PATH" APP=tales-forge SHA=abc123 CONFIG="${CONFIG:-}" "$script" > "$dir/stdout" 2>&1
  local got_exit=$?
  local got_deploys
  got_deploys=$(grep -c '^flyctl deploy' "$dir/calls")
  if [ "$got_exit" = "$want_exit" ] && [ "$got_deploys" = "$want_deploys" ] && check "$dir"; then
    echo "ok   $name (exit $got_exit, $got_deploys deploy)"
  else
    echo "FAIL $name (exit $got_exit want $want_exit, deploys $got_deploys want $want_deploys)"
    fails=$((fails + 1))
  fi
  sed 's/^/       /' "$dir/calls"
  rm -rf "$dir"
}

# The retry deploys the image of the first attempt, does not build, and
# destroys nothing (flyctl cleans up the stuck machine itself).
retry_uses_image() {
  sed -n 2p "$1/calls" | grep -q -- "--image $image$" &&
    ! sed -n 2p "$1/calls" | grep -q -- --remote-only &&
    ! grep -q 'machine destroy' "$1/calls"
}
check() { :; }

run "success, no retry" 0 1 "0:$ok"
check() { retry_uses_image "$1"; }
run "green machine never started, retried" 0 2 "1:$green_stuck" "0:$ok"
run "release machine never started, retried" 0 2 "1:$release_stuck" "0:$ok"
check() { :; }
run "green machine never started twice, one retry only" 1 2 "1:$green_stuck" "1:$green_stuck"
run "build failed, not retried" 1 1 "1:$build_failed"
run "long migration, not retried" 1 1 "1:$long_migration"
run "green machine unhealthy, not retried" 1 1 "1:$unhealthy"
# Playtest (not bluegreen) passes CONFIG: the retry keeps that fly.toml.
check() { retry_uses_image "$1" && sed -n 2p "$1/calls" | grep -q -- '-c fly.playtest.toml'; }
CONFIG=fly.playtest.toml run "playtest config kept on the retry" 0 2 "1:$release_stuck" "0:$ok"

if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
