#!/usr/bin/env bash
# flyctl deploy for playtest.yml and deploy-production.yml, with one retry
# when the release_command machine never starts.
#
# Twice on 2026-10-17 (85e767b4199638 at 12:18, 8151d1a9511618 at 15:40)
# the release machine stayed in "created": Fly placed it in arn and its
# events stop at "created/launch", with no private IP. The first never
# finished pulling the image, the second pulled it in 4 s but never got to
# "Configuring firecracker". A good release machine is stopped (ready) about
# 5 s after it is created. flyctl waits --wait-timeout (default 5m) for that,
# then fails the deploy and destroys the machine.
#
# So: --wait-timeout 2m (it also bounds an app machine's start and health
# check, which take about 15 s), and when the release machine timed out
# before it ever started, deploy the same pushed image once more. A
# migration that runs long is bounded by --release-command-timeout
# (unchanged, 5m) and is never retried: the retry needs the machine to have
# never reached "stopped".
#
# Env: APP (Fly app), SHA (the commit, baked into the image as GIT_SHA),
# CONFIG (optional fly.toml path), FLY_USE_DEPOT (optional).
set -uo pipefail

args=(-a "$APP" --ha=false --wait-timeout 2m)
if [ -n "${CONFIG:-}" ]; then args+=(-c "$CONFIG"); fi

log=$(mktemp)
flyctl deploy "${args[@]}" --remote-only --depot="${FLY_USE_DEPOT:-false}" \
  --build-arg GIT_SHA="$SHA" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if [ "$status" -eq 0 ]; then exit 0; fi

machine=$(grep -oE 'Created release_command machine [0-9a-f]+' "$log" | tail -1 | awk '{print $4}')
image=$(grep -oE 'registry\.fly\.io/[a-z0-9-]+:deployment-[A-Z0-9]+' "$log" | tail -1)
if [ -z "$machine" ] || [ -z "$image" ] ||
  ! grep -q "error running release_command machine: timeout reached" "$log" ||
  grep -q "Machine $machine has state: stopped" "$log"; then
  exit "$status"
fi

echo "::warning title=Release machine never started::$machine stayed in created; deploying $image once more."
flyctl deploy "${args[@]}" --image "$image"
