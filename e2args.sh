#!/usr/bin/env bash

# sanity - exit on any error; no unbound variables
set -euo pipefail

E2ARGS_NAMES=()
E2ARGS_REQUIRED=()
E2ARGS_VALIDATORS=()
E2ARGS_SEPARATORS=()

function e2args-names() {
	E2ARGS_NAMES=("$@")
}

function e2args-required() {
	E2ARGS_REQUIRED=("$@")
}

function e2args-validators() {
	E2ARGS_VALIDATORS=("$@")
}

function e2args-separators() {
	E2ARGS_SEPARATORS=("$@")
}

function e2args-unset() {
	unset ARGS
	unset E2ARGS_NAMES
	unset E2ARGS_REQUIRED
	unset E2ARGS_VALIDATORS
	unset E2ARGS_SEPARATORS
}

function e2args() {
	# script arguments:
	local args=("$@")

	# local array vars defined to provide parameters for argument parsing
	# ARGS array required; rest optional
	# ARGS array populated with resulting argument values
	local argNames=()
	if [[ -n "${ARGS:-}" ]]; then
		argNames=("${ARGS[@]}") # allow passing in names via ARGS
	fi
	(( ${#E2ARGS_NAMES[@]} > 0 )) && argNames=("${E2ARGS_NAMES[@]}")
	local required=()
	(( ${#E2ARGS_REQUIRED[@]} > 0 )) && required=("${E2ARGS_REQUIRED[@]}")
	local validators=()
	(( ${#E2ARGS_VALIDATORS[@]} > 0 )) && validators=("${E2ARGS_VALIDATORS[@]}")
	local separators=("" "=" ":")
	(( ${#E2ARGS_SEPARATORS[@]} > 0 )) && separators=("${E2ARGS_SEPARATORS[@]}")

	local argResults=()
	local argErrors=()
	local extraArgErrors=()

	# locals used during arg processing:
	local i
	local j
	local sep
	local sepRegExp
	local argIdx
	local argName
	local argChars
	local argChar
	local argValue
	local argValueSet
	local argValidator
	local argNext
	local argNextIdx
	local req
	local reqCount
	local reqChecks=()
	local reqArgs=()
	local reqOps=()
	local reqStart=()

	# argChars: first letter of each arg name, concatenated into a string
	# e.g. ("get" "put" "new")
	# >>> "gpn"
	argChars=""
	for (( i = 0 ; i < "${#argNames[@]}" ; i++ )); do
		argChars+="${argNames[${i}]:0:1}"
		argErrors+=( "" )
		argResults+=( "" )
	done

	# argSeparators: provided SEPARATORS array concatenated into a string
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

	# iterate through args
	for (( argIdx = 0 ; argIdx < "${#args[@]}" ; argIdx++ )); do
		arg="${args[${argIdx}]-}"
		argValue=""

		# handle flag combinations
		# e.g. -gpn
		# >>> ['-g', '-p', '-n']
		if [[ "${arg}" =~ ^-[${argChars}][${argChars}]+$ ]]; then
			arg="${arg#-}" # strip "-" prefix
			for (( i = 0 ; i < ${#arg} ; i++ )); do
				args+=( "-${arg:i:1}" )
			done
			continue
		fi

		argValueSet=false

		# iterate through arg names; check each to see if arg matches
		for (( i = 0 ; i < ${#argNames[@]} ; i++ )); do
			argName="${argNames[${i}]}"
			argChar="${argChars:${i}:1}"
			argValidator="${validators[${i}]-}"

			# if arg starts with pattern matching --name or -n (first char of arg name)
			if [[ "${arg}" =~ ^(--${argName}|-${argChar}) ]]; then

				# check if arg matches --name<sep>value format
				# e.g. --get=foo --put:bar -n5
				# >>> ['foo', 'bar', '5']
				for (( j = 0 ; j < ${#separators[@]} ; j++ )); do
					sep="${separators[${j}]}"

					# special case: sep=""
					if [[ "${sep}" == "" ]]; then
						if [[ "${arg}" =~ ^--${argName}.+$ ]]; then
							argValue="${arg#*--${argName}}"
							argValueSet=true
						elif [[ "${arg}" =~ ^-${argChar}.+$ ]]; then
							argValue="${arg#*-${argChar}}"
							argValueSet=true
						fi
					else
						if [[ "${arg}" =~ ^--${argName}${sep} ]]; then
							argValue="${arg#*--${argName}${sep}}"
							argValueSet=true
						elif [[ "${arg}" =~ ^-${argChar}${sep} ]]; then
							argValue="${arg#*-${argChar}${sep}}"
							argValueSet=true
						fi
					fi
				done

				# if next arg does not start with '-', treat as arg value
				# e.g. --get foo --put bar -n 5
				# >>> ['foo', 'bar', '5']
				if [[ "${argValueSet}" == false ]]; then
					argNextIdx="$(( argIdx + 1 ))"
					if (( "${argNextIdx}" < "${#args[@]}" )); then
						argNext="${args[${argNextIdx}]}"
						if ! [[ "${argNext}" =~ ^- ]]; then
							argValue="${argNext}"
							argValueSet=true
							(( argIdx++ )) || true
						fi
					fi
				fi

				# otherwise, treat arg as a flag
				# e.g. --get --put -n
				# >>> ['-g', '-p', '-n']
				if [[ "${argValueSet}" == false ]]; then
					argValue="-${argChar}"
					argValueSet=true
				fi

				# arg type validation
				if [[ -n "${argValidator}" ]]; then
					case "${argValidator}" in
						"str" | "string")
							if [[ "${argValue}" =~ ^-${argChar}$ ]]; then
								argErrors[${i}]="Error: ${arg} argument is invalid (must be a string value, but was passed as a boolean flag)"
							fi
							;;
						"int" | "integer")
							if ! [[ "${argValue}" =~ ^[0-9]+$ ]]; then
								argErrors[${i}]="Error: ${arg} argument is invalid (must be an integer, but was provided value '${argValue}')"
							fi
							;;
						"bool" | "boolean")
							if ! [[ "${argValue}" =~ ^-${argChar}$ ]]; then
								argErrors[${i}]="Error: ${arg} argument is invalid (must be a boolean flag, but was provided value '${argValue}')"
							fi
							;;
						*)
							if ! [[ "${argValue}" =~ ${argValidator} ]]; then
								argErrors[${i}]="Error: ${arg} argument is invalid ('${argValue}' does not match provided validator '${argValidator}')"
							fi
							;;
					esac

				fi

				# output arg value into results array:
				argResults[${i}]="${argValue}"
				break
			fi
		done

		# if no value was set, arg was invalid
		if [[ "${argValueSet}" == false ]]; then
			extraArgErrors+=( "Error: ${arg} argument is invalid (not specified in ARGS array)" )
		fi
	done

	# arg required validation
	if (( "${#required[@]}" > 0 )); then
		reqArgs=()
		reqChecks=()

		# validate arg required entries
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

		# iterate through arg names; check each to see if arg was required
		for (( i = 0 ; i < ${#argNames[@]} ; i++ )); do
			argName="${argNames[${i}]}"
			argChar="${argChars:${i}:1}"
			req="${required[${i}]-}"
			argValue="${argResults[${i}]-}"

			if [[ "${req}" == "true" ]]; then
				if [[ -z "${argValue}" ]]; then
					argErrors[${i}]="Error: --${argName} argument is required but was not provided a value"
				fi
			elif [[ "${req}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
				local reqOp="${req//[0-9]/}" # remove digits
				local reqIdx="${req#${reqOp}}" # get digits

				for (( j = 0 ; j <= reqIdx ; j++ )); do
					if [[ -z "${reqChecks[${j}]:-}" ]]; then
						reqChecks[${j}]=""
						reqArgs[${j}]=""
						reqOps[${j}]=""
						reqStart[${j}]=""
					fi
				done

				reqOps[${reqIdx}]="${reqOp}"
				reqArgs[${reqIdx}]+="--${argName} "

				if [[ "${reqOp}" == "and" ]]; then
					if [[ -z "${argValue}" ]]; then
						reqChecks[${reqIdx}]=false
					fi

				elif [[ "${reqOp}" == "or" ]]; then
					if [[ -z "${reqChecks[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
					fi
					if [[ -n "${argValue}" ]]; then
						reqChecks[${reqIdx}]=true
					fi

				elif [[ "${reqOp}" == "nand" ]]; then
					if [[ -z "${reqChecks[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
					fi
					if [[ -z "${argValue}" ]]; then
						reqChecks[${reqIdx}]=true
					fi

				elif [[ "${reqOp}" == "nor" ]]; then
					if [[ -n "${argValue}" ]]; then
						reqChecks[${reqIdx}]=false
					fi

				elif [[ "${reqOp}" == "xand" || "${reqOp}" == "xnor" ]]; then
					if [[ -z "${reqStart[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=true
						reqStart[${reqIdx}]="undefined"
						if [[ -n "${argValue}" ]]; then
							reqStart[${reqIdx}]="defined"
						fi
					else
						if [[ "${reqStart[${reqIdx}]}" == "undefined" && -n "${argValue}" ]]; then
							reqChecks[${reqIdx}]=false
						elif [[ "${reqStart[${reqIdx}]}" == "defined" && -z "${argValue}" ]]; then
							reqChecks[${reqIdx}]=false
						fi
					fi

				elif [[ "${reqOp}" == "xor" ]]; then
					if [[ -z "${reqStart[${reqIdx}]:-}" ]]; then
						reqChecks[${reqIdx}]=false
						reqStart[${reqIdx}]="undefined"
						if [[ -n "${argValue}" ]]; then
							reqStart[${reqIdx}]="defined"
						fi
					else
						if [[ "${reqStart[${reqIdx}]}" == "undefined" && -n "${argValue}" ]]; then
							reqChecks[${reqIdx}]=true
						elif [[ "${reqStart[${reqIdx}]}" == "defined" && -z "${argValue}" ]]; then
							reqChecks[${reqIdx}]=true
						fi
					fi
				fi

			elif [[ "${req}" != "false" ]]; then
				>&2 echo "Error: invalid ARGS_REQUIRED parameter '${req}' (must match /(true|false|and|or|nand|nor|xand|xnor|xor)[0-9]*/)"
				return 1
			fi
		done

		for (( j = 0 ; j < ${#reqChecks[@]} ; j++ )); do
			if [[ "${reqChecks[${j}]:-}" == false ]]; then
				argErrors[${i}]="Error: ${reqArgs[${j}]}arguments do not satisfy ${reqOps[${j}]} condition"
			fi
		done
	fi

	if (( ${#extraArgErrors[@]} > 0 )); then
		argErrors+=("${extraArgErrors[@]}")
	fi

	# if there were errors, output them over stderr and return through ARGS array
	# otherwise, return arg values/results through ARGS array
	for (( i = 0 ; i < ${#argErrors[@]} ; i++ )); do
		argError="${argErrors[${i}]}"
		if [[ -n "${argError}" ]]; then
			echo "${argError}" >&2
			argResults[${i}]="${argError}"
		fi
	done

	# "return" via ARGS env var
	# shellcheck disable=SC2034
	ARGS=("${argResults[@]}")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	e2args "$@"
fi
