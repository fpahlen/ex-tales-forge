#!/usr/bin/env bash
# flyctl deploy for playtest.yml and deploy-production.yml, with one
# redeploy of the same pushed image when Fly never starts a machine of the
# deploy (it stays in "created").
# Test: .github/scripts/fly_deploy_test.sh (fake flyctl, runs in CI).
#
# - Release machine: twice on 2026-10-17 (85e767b4199638 at 12:18,
#   8151d1a9511618 at 15:40) it stayed in "created": Fly placed it in arn
#   and its events stop at "created/launch", with no private IP. flyctl
#   fails the deploy and destroys the machine.
# - Green machine: the same stall hit the bluegreen green machine of
#   whyse-ab/workflow, also in arn, twice on 2026-10-18 (Deploy run
#   39150156882): the migration ran, the green machine got no start event,
#   and flyctl rolled back and deleted it ("could not get all green machines
#   into started state").
#
# --wait-timeout 2m bounds both waits (a good release machine is stopped
# about 5 s after it is created; an app machine starts and passes its health
# check in about 15 s). Not retried: a build failure, a long migration (it
# reached "stopped"; --release-command-timeout, unchanged at 5m, bounds it),
# a green machine that started but failed its health check, and any other
# error.
#
# Env: APP (Fly app), SHA (the commit, baked into the image as GIT_SHA),
# CONFIG (optional fly.toml path), FLY_USE_DEPOT (optional).
set -uo pipefail

args=(-a "$APP" --ha=false --wait-timeout 2m)
if [ -n "${CONFIG:-}" ]; then args+=(-c "$CONFIG"); fi

log=$(mktemp)
deploy() {
  flyctl deploy "${args[@]}" "$@" 2>&1 | tee "$log"
  return "${PIPESTATUS[0]}"
}

deploy --remote-only --depot="${FLY_USE_DEPOT:-false}" --build-arg GIT_SHA="$SHA"
status=$?
if [ "$status" -eq 0 ]; then exit 0; fi

image=$(grep -oE 'registry\.fly\.io/[a-z0-9-]+:deployment-[A-Z0-9]+' "$log" | tail -1)
release=$(grep -oE 'Created release_command machine [0-9a-f]+' "$log" | tail -1 | awk '{print $4}')
if [ -z "$image" ]; then
  exit "$status"
elif [ -n "$release" ] && ! grep -q "Machine $release has state: stopped" "$log" &&
  grep -q 'error running release_command machine: timeout reached' "$log"; then
  echo "::warning title=Release machine never started::$release stayed in created; deploying $image once more."
elif grep -q 'could not get all green machines into started state' "$log"; then
  echo "::warning title=Green machine never started::deploying $image once more."
else
  exit "$status"
fi

deploy --image "$image"
