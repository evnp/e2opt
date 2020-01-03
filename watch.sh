#!/usr/bin/env bash

# usage: ./watch "command" "pattern" "filter"
#		e.g. ./watch "npm test" "bats" "basic"
# command (required): command to run on file changes
# pattern (optional): kill processes matching pattern between iterations
# filter	(optional): set N, R env vars to only run tests matching string

if ! hash fswatch 2>/dev/null; then
	echo "Error: 'fswatch' not installed (try 'brew install fswatch')"
	return 1
fi

function watch() {
	$1 &

	fswatch --one-per-batch --recursive . | while read -r; do
		[[ -n $2 ]] && pkill -f "$2"
		$1 &
	done
}

# allow running specific tests by index or regex:
if [[ "$3" =~ ^[0-9]+$ ]]; then
	N="$3" watch "$@" | grep --invert-match "skip"
elif [[ -n "$3" ]]; then
	R="$3" watch "$@" | grep --invert-match "skip"
else
	watch "$@"
fi
