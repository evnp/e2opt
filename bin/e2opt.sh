#!/usr/bin/env bash

E2OPT_NAMES=()
E2OPT_RULES=()
E2OPT_TYPES=()
E2OPT_SEPARATORS=()

function e2opt() {
	local command="$1"
	shift

	if [[ "${command}" == "--help" || "${command}" == "-h" ]]; then
		echo "Usage:"
		echo "e2opt [--names|--rules|--types|--separators|--set|--unset] [value [value [value...]]]"
		echo "ex."
		echo "function myFunc() {"
		echo "	e2opt --names aardvark badger crocodile"
		echo "	e2opt --set \"\$@\" ; set -- \"\${OPTIONS[@]}\""
		echo "	e2opt --unset  # unset OPTIONS env var"
		echo "	echo \"\$1 \$2 \$3\""
		echo "}"
		echo "myFunc -c foo --ardvark=bar -bbaz ; set -- \"\${OPTIONS[@]}\""
		echo "bar baz foo"
		echo ""
		echo "See https://github.com/evnp/e2opt for full documentation."

	elif [[ "${command}" == "--names" ]]; then
		E2OPT_NAMES=("$@")

	elif [[ "${command}" == "--rules" ]]; then
		E2OPT_RULES=("$@")

	elif [[ "${command}" == "--types" ]]; then
		E2OPT_TYPES=("$@")

	elif [[ "${command}" == "--separators" ]]; then
		E2OPT_SEPARATORS=("$@")

	elif [[ "${command}" == "--unset" ]]; then
		unset OPTIONS
		unset E2OPT_NAMES
		unset E2OPT_RULES
		unset E2OPT_TYPES
		unset E2OPT_SEPARATORS

	elif ! [[ "${command}" == "--set" ]]; then
		>&2 echo "Error: '${command}' is an invalid e2opts command. "
		echo ""
		e2opt --help
		return 1

	else
		# script arguments:
		local arguments=("$@")
		local optNames=()
		if [[ -n "${OPTIONS:-}" ]]; then
			optNames=("${OPTIONS[@]-}") # allow passing in names via OPTIONS
		fi
		(( ${#E2OPT_NAMES[@]-} > 0 )) && optNames=("${E2OPT_NAMES[@]}")
		local rules=()
		if [[ -n "${E2OPT_RULES:-}" ]]; then
			(( ${#E2OPT_RULES[@]-} > 0 )) && rules=("${E2OPT_RULES[@]}")
		fi
		local types=()
		if [[ -n "${E2OPT_TYPES:-}" ]]; then
			(( ${#E2OPT_TYPES[@]-} > 0 )) && types=("${E2OPT_TYPES[@]}")
		fi
		local separators=("" "=" ":")
		if [[ -n "${E2OPT_SEPARATORS:-}" ]]; then
			(( ${#E2OPT_SEPARATORS[@]-} > 0 )) && separators=("${E2OPT_SEPARATORS[@]}")
		fi

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
		local optType
		local optNext
		local rule
		local ruleCount
		local ruleChecks=()
		local ruleOpts=()
		local ruleOps=()
		local ruleStart=()

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
				optType="${types[${i}]-}"

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
					if [[ -n "${optType}" ]]; then
						case "${optType}" in
							"str" | "string")
								if [[ "${optValue}" =~ ^-${optChar}$ ]]; then
									optErrors[${i}]="Error: '${arg}' is invalid ('${optValue}' must be a string value)."
								fi
								;;
							"int" | "integer")
								if ! [[ "${optValue}" =~ ^[0-9]+$ ]]; then
									optErrors[${i}]="Error: '${arg}' is invalid ('${optValue}' must be an integer)."
								fi
								;;
							"bool" | "boolean")
								if ! [[ "${optValue}" =~ ^-${optChar}$ ]]; then
									optErrors[${i}]="Error: '${arg}' is invalid ('${optValue}' must be a boolean flag)."
								fi
								;;
							*)
								if ! [[ "${optValue}" =~ ${optType} ]]; then
									optErrors[${i}]="Error: '${arg}' is invalid ('${optValue}' must match format '${optType}')."
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
				extraOptErrors+=("Error: '${arg}' is invalid.")
			fi
		done

		# rules option validation
		if (( "${#rules[@]}" > 0 )); then
			ruleOpts=()
			ruleChecks=()

			# validate opt rules entries
			for (( i = 0 ; i < ${#rules[@]} ; i++ )); do
				rule="${rules[${i}]}"
				if [[ "${rule}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
					ruleCount=0
					for (( j = 0 ; j < ${#rules[@]} ; j++ )); do
						if [[ "${rule}" == "${rules[${j}]}" ]]; then
							(( ruleCount++ ))
						fi
					done
					if (( ruleCount == 1 )); then
						>&2 echo "Error: only 1 instance of '${rule}' found in rules array. This is ambiguous; use true/false instead."
						return 1
					fi
				elif ! [[ "${rule}" == "true" || "${rule}" == "false" ]]; then
					>&2 echo "Error: '${rule}' in rules array is invalid."
					return 1
				fi
			done

			# iterate through option names; check each to see if option was rules
			for (( i = 0 ; i < ${#optNames[@]} ; i++ )); do
				optName="${optNames[${i}]}"
				optChar="${optChars:${i}:1}"
				rule="${rules[${i}]-}"
				optValue="${optResults[${i}]-}"

				if [[ "${rule}" == "true" ]]; then
					if [[ -z "${optValue}" ]]; then
						optErrors[${i}]="Error: --${optName} is rules but was not provided a value."
					fi
				elif [[ "${rule}" =~ ^(and|or|nand|nor|xand|xnor|xor)[0-9]*$ ]]; then
					local ruleOp="${rule//[0-9]/}" # remove digits
					local ruleIdx="${rule#${ruleOp}}" # get digits

					for (( j = 0 ; j <= ruleIdx ; j++ )); do
						if [[ -z "${ruleChecks[${j}]:-}" ]]; then
							ruleChecks[${j}]=""
							ruleOpts[${j}]=""
							ruleOps[${j}]=""
							ruleStart[${j}]=""
						fi
					done

					ruleOps[${ruleIdx}]="${ruleOp}"
					ruleOpts[${ruleIdx}]+="--${optName} "

					if [[ "${ruleOp}" == "and" ]]; then
						if [[ -z "${optValue}" ]]; then
							ruleChecks[${ruleIdx}]=false
						fi

					elif [[ "${ruleOp}" == "or" ]]; then
						if [[ -z "${ruleChecks[${ruleIdx}]:-}" ]]; then
							ruleChecks[${ruleIdx}]=false
						fi
						if [[ -n "${optValue}" ]]; then
							ruleChecks[${ruleIdx}]=true
						fi

					elif [[ "${ruleOp}" == "nand" ]]; then
						if [[ -z "${ruleChecks[${ruleIdx}]:-}" ]]; then
							ruleChecks[${ruleIdx}]=false
						fi
						if [[ -z "${optValue}" ]]; then
							ruleChecks[${ruleIdx}]=true
						fi

					elif [[ "${ruleOp}" == "nor" ]]; then
						if [[ -n "${optValue}" ]]; then
							ruleChecks[${ruleIdx}]=false
						fi

					elif [[ "${ruleOp}" == "xand" || "${ruleOp}" == "xnor" ]]; then
						if [[ -z "${ruleStart[${ruleIdx}]:-}" ]]; then
							ruleChecks[${ruleIdx}]=true
							ruleStart[${ruleIdx}]="undefined"
							if [[ -n "${optValue}" ]]; then
								ruleStart[${ruleIdx}]="defined"
							fi
						else
							if [[ "${ruleStart[${ruleIdx}]}" == "undefined" && -n "${optValue}" ]]; then
								ruleChecks[${ruleIdx}]=false
							elif [[ "${ruleStart[${ruleIdx}]}" == "defined" && -z "${optValue}" ]]; then
								ruleChecks[${ruleIdx}]=false
							fi
						fi

					elif [[ "${ruleOp}" == "xor" ]]; then
						if [[ -z "${ruleStart[${ruleIdx}]:-}" ]]; then
							ruleChecks[${ruleIdx}]=false
							ruleStart[${ruleIdx}]="undefined"
							if [[ -n "${optValue}" ]]; then
								ruleStart[${ruleIdx}]="defined"
							fi
						else
							if [[ "${ruleStart[${ruleIdx}]}" == "undefined" && -n "${optValue}" ]]; then
								ruleChecks[${ruleIdx}]=true
							elif [[ "${ruleStart[${ruleIdx}]}" == "defined" && -z "${optValue}" ]]; then
								ruleChecks[${ruleIdx}]=true
							fi
						fi
					fi

				elif [[ "${rule}" != "false" ]]; then
					>&2 echo "Error: invalid rules parameter '${rule}' (must match /(true|false|and|or|nand|nor|xand|xnor|xor)[0-9]*/)."
					return 1
				fi
			done

			for (( j = 0 ; j < ${#ruleChecks[@]} ; j++ )); do
				if [[ "${ruleChecks[${j}]:-}" == false ]]; then
					optErrors[${i}]="Error: '${ruleOpts[${j}]}' do not satisfy '${ruleOps[${j}]}' condition."
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
				>&2 echo "${optError}"
				optResults[${i}]="${optError}"
			fi
		done

		# "return" via OPTIONS env var
		# shellcheck disable=SC2034
		OPTIONS=("${optResults[@]}")
		# may be used in script to update option env vars $@, $1, $2, etc., e.g.
		# e2opt "$@" ; set -- "${OPTIONS[@]}"  // process options and pass into $@, $1, $2, etc.
		# e2opt-unset													 // clean up e2opt env vars if desired
	fi
}

# allow sourcing script or executing it directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	e2opt "$@"
fi
