#!/usr/bin/env bash

# sanity - exit on any error; no unbound variables
set -euo pipefail

E2OPT_NAMES=()
E2OPT_REQUIRED=()
E2OPT_VALIDATORS=()
E2OPT_SEPARATORS=()

function e2opt-names() {
	E2OPT_NAMES=("$@")
}

function e2opt-required() {
	E2OPT_REQUIRED=("$@")
}

function e2opt-validators() {
	E2OPT_VALIDATORS=("$@")
}

function e2opt-separators() {
	E2OPT_SEPARATORS=("$@")
}

function e2opt-unset() {
	unset OPTIONS
	unset E2OPT_NAMES
	unset E2OPT_REQUIRED
	unset E2OPT_VALIDATORS
	unset E2OPT_SEPARATORS
}

function e2opt() {
	# script arguments:
	local arguments=("$@")
	local optNames=()
	if [[ -n "${OPTIONS:-}" ]]; then
		optNames=("${OPTIONS[@]}") # allow passing in names via OPTIONS
	fi
	(( ${#E2OPT_NAMES[@]} > 0 )) && optNames=("${E2OPT_NAMES[@]}")
	local required=()
	(( ${#E2OPT_REQUIRED[@]} > 0 )) && required=("${E2OPT_REQUIRED[@]}")
	local validators=()
	(( ${#E2OPT_VALIDATORS[@]} > 0 )) && validators=("${E2OPT_VALIDATORS[@]}")
	local separators=("" "=" ":")
	(( ${#E2OPT_SEPARATORS[@]} > 0 )) && separators=("${E2OPT_SEPARATORS[@]}")

	local optResults=()
	local optErrors=()
	local extraOptErrors=()

	# locals used during option processing:
	local i
	local j
	local arg
	local argIdx
	local argNextIdx
	local sep
	local sepRegExp
	local optName
	local optChars
	local optChar
	local optValue
	local optValueSet
	local optValidator
	local optNext
	local req
	local reqCount
	local reqChecks=()
	local reqOpts=()
	local reqOps=()
	local reqStart=()

	# optChars: first letter of each option name, concatenated into a string
	# e.g. ("get" "put" "new")
	# >>> "gpn"
	optChars=""
	for (( i = 0 ; i < "${#optNames[@]}" ; i++ )); do
		optChars+="${optNames[${i}]:0:1}"
		optErrors+=( "" )
		optResults+=( "" )
	done

	# optSeparators: provided SEPARATORS array concatenated into a string
	# e.g. ("" "=" ":")
	# >>> "(=|:)"
	sepRegExp=""
	for (( i = 0 ; i < "${#separators[@]}" ; i++ )); do
		sep="${separators[${i}]}"
		if [[ -n "${sep}" ]]; then
			if [[ -n "${sepRegExp}" ]]; then
				sepRegExp+="|${sep}"
			else
				sepRegExp+="${sep}"
			fi
		fi
		sepRegExp="(${sepRegExp})"
	done

	# iterate through options
	for (( argIdx = 0 ; argIdx < "${#arguments[@]}" ; argIdx++ )); do
		arg="${arguments[${argIdx}]-}"
		optValue=""

		# handle flag combinations
		# e.g. -gpn
		# >>> ['-g', '-p', '-n']
		if [[ "${arg}" =~ ^-[${optChars}][${optChars}]+$ ]]; then
			arg="${arg#-}" # strip "-" prefix
			for (( i = 0 ; i < ${#arg} ; i++ )); do
				arguments+=( "-${arg:i:1}" )
			done
			continue
		fi

		optValueSet=false

		# iterate through option names; check each to see if argument matches
		for (( i = 0 ; i < ${#optNames[@]} ; i++ )); do
			optName="${optNames[${i}]}"
			optChar="${optChars:${i}:1}"
			optValidator="${validators[${i}]-}"

			# if argument starts with pattern matching --name or -n (first char of option name)
			if [[ "${arg}" =~ ^(--${optName}|-${optChar}) ]]; then

				# check if argument matches --name<sep>value format
				# e.g. --get=foo --put:bar -n5
				# >>> ['foo', 'bar', '5']
				for (( j = 0 ; j < ${#separators[@]} ; j++ )); do
					sep="${separators[${j}]}"

					# special case: sep=""
					if [[ "${sep}" == "" ]]; then
						if [[ "${arg}" =~ ^--${optName}.+$ ]]; then
							optValue="${arg#*--${optName}}"
							optValueSet=true
						elif [[ "${arg}" =~ ^-${optChar}.+$ ]]; then
							optValue="${arg#*-${optChar}}"
							optValueSet=true
						fi
					else
						if [[ "${arg}" =~ ^--${optName}${sep} ]]; then
							optValue="${arg#*--${optName}${sep}}"
							optValueSet=true
						elif [[ "${arg}" =~ ^-${optChar}${sep} ]]; then
							optValue="${arg#*-${optChar}${sep}}"
							optValueSet=true
						fi
					fi
				done

				# if next argument does not start with '-', treat as argument value
				# e.g. --get foo --put bar -n 5
				# >>> ['foo', 'bar', '5']
				if [[ "${optValueSet}" == false ]]; then
					argNextIdx="$(( argIdx + 1 ))"
					if (( "${argNextIdx}" < "${#arguments[@]}" )); then
						optNext="${arguments[${argNextIdx}]}"
						if ! [[ "${optNext}" =~ ^- ]]; then
							optValue="${optNext}"
							optValueSet=true
							(( argIdx++ )) || true
						fi
					fi
				fi

				# otherwise, treat argument as a flag
				# e.g. --get --put -n
				# >>> ['-g', '-p', '-n']
				if [[ "${optValueSet}" == false ]]; then
					optValue="-${optChar}"
					optValueSet=true
				fi

				# option type validation
				if [[ -n "${optValidator}" ]]; then
					case "${optValidator}" in
						"str" | "string")
							if [[ "${optValue}" =~ ^-${optChar}$ ]]; then
								optErrors[${i}]="Error: ${arg} is invalid (must be a string value, but was passed as a boolean flag)."
							fi
							;;
						"int" | "integer")
							if ! [[ "${optValue}" =~ ^[0-9]+$ ]]; then
								optErrors[${i}]="Error: ${arg} is invalid (must be an integer, but was provided value '${optValue}')."
							fi
							;;
						"bool" | "boolean")
							if ! [[ "${optValue}" =~ ^-${optChar}$ ]]; then
								optErrors[${i}]="Error: ${arg} is invalid (must be a boolean flag, but was provided value '${optValue}')."
							fi
							;;
						*)
							if ! [[ "${optValue}" =~ ${optValidator} ]]; then
								optErrors[${i}]="Error: ${arg} is invalid ('${optValue}' does not match provided validator '${optValidator}')."
							fi
							;;
					esac

				fi

				# output option value into results array:
				optResults[${i}]="${optValue}"
				break
			fi
		done

		# if no value was set, option is invalid
		if [[ "${optValueSet}" == false ]]; then
			extraOptErrors+=("Error: ${arg} is invalid.")
		fi
	done

	# required option validation
	if (( "${#required[@]}" > 0 )); then
		reqOpts=()
		reqChecks=()

		# validate opt required entries
		for (( i = 0 ; i < ${#required[@]} ; i++ )); do
			req="${required[${i}]}"
			if [[ "${req}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
				reqCount=0
				for (( j = 0 ; j < ${#required[@]} ; j++ )); do
					if [[ "${req}" == "${required[${j}]}" ]]; then
						(( reqCount++ ))
					fi
				done
				if (( reqCount == 1 )); then
					echo "Error: only 1 instance of ${req} found in required array. This is ambiguous; use true/false instead."
					return 1
				fi
			elif ! [[ "${req}" == "true" || "${req}" == "false" ]]; then
				echo "Error: ${req} in required array is invalid."
				return 1
			fi
		done

		# iterate through option names; check each to see if option was required
		for (( i = 0 ; i < ${#optNames[@]} ; i++ )); do
			optName="${optNames[${i}]}"
			optChar="${optChars:${i}:1}"
			req="${required[${i}]-}"
			optValue="${optResults[${i}]-}"

			if [[ "${req}" == "true" ]]; then
				if [[ -z "${optValue}" ]]; then
					optErrors[${i}]="Error: --${optName} is required but was not provided a value."
				fi
			elif [[ "${req}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
				local reqOp="${req//[0-9]/}" # remove digits
				local reqIdx="${req#${reqOp}}" # get digits

				for (( j = 0 ; j <= reqIdx ; j++ )); do
					if [[ -z "${reqChecks[${j}]:-}" ]]; then
						reqChecks[${j}]=""
						reqOpts[${j}]=""
						reqOps[${j}]=""
						reqStart[${j}]=""
					fi
				done

				reqOps[${reqIdx}]="${reqOp}"
				reqOpts[${reqIdx}]+="--${optName} "

				if [[ "${reqOp}" == "and" ]]; then
					if [[ -z "${optValue}" ]]; then
						reqChecks[${reqIdx}]=false
					fi

				elif [[ "${reqOp}" == "or" ]]; then
					if [[ -z "${reqChecks[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
					fi
					if [[ -n "${optValue}" ]]; then
						reqChecks[${reqIdx}]=true
					fi

				elif [[ "${reqOp}" == "nand" ]]; then
					if [[ -z "${reqChecks[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
					fi
					if [[ -z "${optValue}" ]]; then
						reqChecks[${reqIdx}]=true
					fi

				elif [[ "${reqOp}" == "nor" ]]; then
					if [[ -n "${optValue}" ]]; then
						reqChecks[${reqIdx}]=false
					fi

				elif [[ "${reqOp}" == "xand" || "${reqOp}" == "xnor" ]]; then
					if [[ -z "${reqStart[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=true
						reqStart[${reqIdx}]="undefined"
						if [[ -n "${optValue}" ]]; then
							reqStart[${reqIdx}]="defined"
						fi
					else
						if [[ "${reqStart[${reqIdx}]}" == "undefined" && -n "${optValue}" ]]; then
							reqChecks[${reqIdx}]=false
						elif [[ "${reqStart[${reqIdx}]}" == "defined" && -z "${optValue}" ]]; then
							reqChecks[${reqIdx}]=false
						fi
					fi

				elif [[ "${reqOp}" == "xor" ]]; then
					if [[ -z "${reqStart[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
						reqStart[${reqIdx}]="undefined"
						if [[ -n "${optValue}" ]]; then
							reqStart[${reqIdx}]="defined"
						fi
					else
						if [[ "${reqStart[${reqIdx}]}" == "undefined" && -n "${optValue}" ]]; then
							reqChecks[${reqIdx}]=true
						elif [[ "${reqStart[${reqIdx}]}" == "defined" && -z "${optValue}" ]]; then
							reqChecks[${reqIdx}]=true
						fi
					fi
				fi

			elif [[ "${req}" != "false" ]]; then
				>&2 echo "Error: invalid required parameter '${req}' (must match /(true|false|and|or|nand|nor|xand|xnor|xor)[0-9]*/)."
				return 1
			fi
		done

		for (( j = 0 ; j < ${#reqChecks[@]} ; j++ )); do
			if [[ "${reqChecks[${j}]:-}" == false ]]; then
				optErrors[${i}]="Error: ${reqOpts[${j}]} do not satisfy ${reqOps[${j}]} condition."
			fi
		done
	fi

	if (( ${#extraOptErrors[@]} > 0 )); then
		optErrors+=("${extraOptErrors[@]}")
	fi

	# if there were errors, output them over stderr and return through OPTIONS array
	# otherwise, return option values through OPTIONS array
	for (( i = 0 ; i < ${#optErrors[@]} ; i++ )); do
		optError="${optErrors[${i}]}"
		if [[ -n "${optError}" ]]; then
			echo "${optError}" >&2
			optResults[${i}]="${optError}"
		fi
	done

	# "return" via OPTIONS env var
	# shellcheck disable=SC2034
	OPTIONS=("${optResults[@]}")
  # may be used in script to update option env vars $@, $1, $2, etc., e.g.
  # e2opt "$@" ; set -- "${OPTIONS[@]}"  // process options and pass into $@, $1, $2, etc.
  # e2opt-unset                          // clean up e2opt env vars if desired
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	e2opt "$@"
fi
