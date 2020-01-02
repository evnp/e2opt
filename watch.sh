#!/usr/bin/env bash

# usage: ./watch "command" "pattern"
#   e.g. ./watch "npm test" "bats"
# command (required): command to run on file changes
# pattern (optional): kill processes matching pattern between iterations

if ! hash fswatch 2>/dev/null; then
	echo "Error: 'fswatch' not installed (try 'brew install fswatch')"
	return 1
fi

$1 &

fswatch --one-per-batch --recursive . | while read -r; do
	[[ -n $2 ]] && pkill -f "$2"
	$1 &
done
