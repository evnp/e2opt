#!/usr/bin/env bash

# sanity - exit on any error; no unbound variables
#set -eo pipefail

E2ARGS_NAMES=()
E2ARGS_REQUIRED=()
E2ARGS_VALIDATORS=()
E2ARGS_SEPARATORS=()

e2args-names() {
  E2ARGS_NAMES=("$@")
}

e2args-required() {
  E2ARGS_REQUIRED=("$@")
}

e2args-validators() {
  E2ARGS_VALIDATORS=("$@")
}

e2args-separators() {
  E2ARGS_SEPARATORS=("$@")
}

e2args() {
	# script arguments:
	local args=("$@")

	# local array vars defined to provide parameters for argument parsing
	# ARGS array required; rest optional
	# ARGS array populated with resulting argument values
	local argNames=("${E2ARGS_NAMES[@]}")
	local required=("${E2ARGS_REQUIRED[@]}")
	local validators=("${E2ARGS_VALIDATORS[@]}")
	local separators=("${E2ARGS_SEPARATORS[@]}")
	if (( "${#separators[@]}" == 0 )); then
		separators=("" "=" ":")
	fi

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
	local argReq
	local argNext
	local argNextIdx
	local argReqChecks=()
	local argReqArgLists=()
	local argReqOperators=()
	local argReqStart=()

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
		argReqArgLists=()
		argReqChecks=()

		# iterate through arg names; check each to see if arg was required
		for (( i = 0 ; i < ${#argNames[@]} ; i++ )); do
			argName="${argNames[${i}]}"
			argChar="${argChars:${i}:1}"
			argReq="${required[${i}]-}"
			argValue="${argResults[${i}]-}"

			if [[ "${argReq}" == "true" ]]; then
				if [[ -z "${argValue}" ]]; then
					argErrors[${i}]="Error: --${argName} argument is required but was not provided a value"
				fi
			elif [[ "${argReq}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
				local argReqOperator="${argReq//[0-9]/}" # remove digits
				local argReqIdx="${argReq#${argReqOperator}}" # get digits

				for (( j = 0 ; j < argReqIdx ; j++ )); do
					if [[ -z "${argReqChecks[${j}]}" ]]; then
						argReqChecks[${j}]=""
						argReqArgLists[${j}]=""
						argReqOperators[${j}]=""
						argReqStart[${j}]=""
					fi
				done

				if [[ -z "${argReqArgLists[${argReqIdx}]}" ]]; then
					argReqArgLists[${argReqIdx}]=""
				fi

				argReqOperators[${argReqIdx}]="${argReqOperator}"
				argReqArgLists[${argReqIdx}]+="--${argName} "

				if [[ "${argReqOperator}" == "and" ]]; then
					if [[ -z "${argValue}" ]]; then
						argReqChecks[${argReqIdx}]=false
					fi
				elif [[ "${argReqOperator}" == "or" ]]; then
					if [[ -z "${argReqChecks[${argReqIdx}]}" ]]; then
						argReqChecks[${argReqIdx}]=false
					fi
					if [[ -n "${argValue}" ]]; then
						argReqChecks[${argReqIdx}]=true
					fi
				elif [[ "${argReqOperator}" == "nand" ]]; then
					if [[ -z "${argReqChecks[${argReqIdx}]}" ]]; then
						argReqChecks[${argReqIdx}]=false
					fi
					if [[ -z "${argValue}" ]]; then
						argReqChecks[${argReqIdx}]=true
					fi
				elif [[ "${argReqOperator}" == "nor" ]]; then
					if [[ -n "${argValue}" ]]; then
						argReqChecks[${argReqIdx}]=false
					fi
				elif [[ "${argReqOperator}" == "xand" || "${argReqOperator}" == "xnor" ]]; then
					if [[ -z "${argReqStart[${argReqIdx}]}" ]]; then
						argReqStart[${argReqIdx}]="undefined"
						if [[ -n "${argValue}" ]]; then
							argReqStart[${argReqIdx}]="defined"
						fi
					else
						if [[ "${argReqStart[${argReqIdx}]}" == "undefined" && -n "${argValue}" ]]; then
							argReqChecks[${argReqIdx}]=false
						elif [[ "${argReqStart[${argReqIdx}]}" == "defined" && -z "${argValue}" ]]; then
							argReqChecks[${argReqIdx}]=false
						fi
					fi
				elif [[ "${argReqOperator}" == "xor" ]]; then
					argReqChecks[${argReqIdx}]=false
					if [[ -z "${argReqStart[${argReqIdx}]}" ]]; then
						argReqStart[${argReqIdx}]="undefined"
						if [[ -n "${argValue}" ]]; then
							argReqStart[${argReqIdx}]="defined"
						fi
					else
						if [[ "${argReqStart[${argReqIdx}]}" == "undefined" && -n "${argValue}" ]]; then
							argReqChecks[${argReqIdx}]=true
						elif [[ "${argReqStart[${argReqIdx}]}" == "defined" && -z "${argValue}" ]]; then
							argReqChecks[${argReqIdx}]=true
						fi
					fi
				fi

			elif [[ "${argReq}" != "false" ]]; then
				>&2 echo "Error: invalid ARGS_REQUIRED parameter '${argReq}' (must match /(true|false|and|or|nand|nor|xand|xnor|xor)[0-9]*/)"
				return 1
			fi
		done

		for (( j = 0 ; j < ${#argReqChecks[@]} ; j++ )); do
			if [[ "${argReqChecks[${j}]}" == false ]]; then
				argErrors[${i}]="Error: ${argReqArgLists[${i}]}arguments do not satisfy ${argReqOperators[${i}]} condition"
			fi
		done
	fi

	argErrors+=("${extraArgErrors[@]}")

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
	ARGS=("${argResults[@]}")
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	e2args "$@"
fi
