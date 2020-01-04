#!/usr/bin/env bash

load './node_modules/bats-support/load'
load './node_modules/bats-assert/load'

# shellcheck disable=SC1090
source "$BATS_TEST_DIRNAME/e2opt.sh"

# N=42 bats test.bats       // run individual test by index
# R=pattern bats test.bats  // run only tests whose descriptions match pattern
function setup() {
	if [[ -n "${N:-}" ]]; then
		if (( BATS_TEST_NUMBER != N )); then
			skip
		fi
	fi
	if [[ -n "${R:-}" ]]; then
		if ! [[ "${BATS_TEST_DESCRIPTION}" =~ ${R} ]]; then
			skip
		fi
	fi
}

function assert_args() {
  local expected=( "$@" )

  # numArgs: max length between OPTIONS and expected arrays
  local numArgs="${#OPTIONS[@]}"
  (( "${#expected[@]}" > numArgs )) && numArgs="${#expected[@]}"

  local i
  for (( i = 0 ; i < numArgs ; i++ )); do
    assert_equal "${OPTIONS[${i}]}" "${expected[${i}]}"
  done
}

@test "boolean flag args : basic           : -a -b -c -d" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -a -b -c -d
  assert_args -a -b -c -d
}

@test "boolean flag args : arbitrary order : -c -a -d -b" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c -a -d -b
  assert_args -a -b -c -d
}

@test "boolean flag args : shorthand       : -acd -b" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -acd -b
  assert_args -a -b -c -d
}

@test "boolean flag args : set             : -a -b -c -d" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -a -b -c -d ; set -- "${OPTIONS[@]}"
  e2opt-unset
  assert [ -z "${OPTIONS+x}" ] # ensure OPTIONS was unset
  assert_equal "$1" -a
  assert_equal "$2" -b
  assert_equal "$3" -c
  assert_equal "$4" -d
}

@test "key/value args    : basic           : -a1 -b=2 -c:3 -d 4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -a1 -b=2 -c:3 -d 4
  assert_args 1 2 3 4
}

@test "key/value args    : arbitrary order : -c:3 -a1 -d 4 -b=2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c:3 -a1 -d 4 -b=2
  assert_args 1 2 3 4
}

@test "key/value args    : string values   : -c:'snap snap' -aslurp -d 'bark bark' -b=" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c:'snap snap' -aslurp -d 'bark bark' -b=
  assert_args 'slurp' '' 'snap snap' 'bark bark'
}

@test "key/value args    : empty values    : -c:'' -a= -d \"\" -b=\"\"" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c:'' -a= -d "" -b=""
  assert_args '' '' '' ''
}

@test "key/value args    : quotes" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c:'' -a= -d "'single'" -b="\"double\""
  assert_args '' "\"double\"" '' "'single'"
}

@test "key/value args   : set             : -c:'snap snap' -aslurp -d '\"bark bark\"' -b=" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -c:'snap snap' -aslurp -d "\"bark bark\"" -b= ; set -- "${OPTIONS[@]}"
  e2opt-unset
  assert [ -z "${OPTIONS+x}" ] # ensure OPTIONS was unset
  assert_equal "$1" "slurp"
  assert_equal "$2" ""
  assert_equal "$3" "snap snap"
  assert_equal "$4" "\"bark bark\""
}

@test "longform args     : integer values  : --aardvark -c 1 --badger 2 --dingo" {
  e2opt-names aardvark badger crocodile dingo
  e2opt --aardvark -c 1 --badger 2 --dingo
  assert_args -a 2 1 -d
}

@test "longform args    : string values   : --aardvark -c 'snap snap' --badgergrowl -d" {
  e2opt-names aardvark badger crocodile dingo
  e2opt --aardvark -c 'snap snap' --badgergrowl -d
  assert_args -a growl 'snap snap' -d
}

@test "longform args    : empty values    : --aardvark -c '' --badger:\"\" --dingo=''" {
  e2opt-names aardvark badger crocodile dingo
  e2opt --aardvark -c '' --badger:"" --dingo=
  assert_args -a '' '' ''
}

@test "longform args    : quotes" {
  e2opt-names aardvark badger crocodile dingo
  e2opt --aardvark -c "'single'" --badger:"\"double\"" --dingo=
  assert_args -a "\"double\"" "'single'" ''
}

@test "longform args    : set             : --aardvark -c 'snap snap' --badger\"growl\"\" -d" {
  e2opt-names aardvark badger crocodile dingo
  e2opt --aardvark -c 'snap snap' --badger"growl\"" -d ; set -- "${OPTIONS[@]}"
  e2opt-unset
  assert [ -z "${OPTIONS+x}" ] # ensure OPTIONS was unset
  assert_equal "$1" "-a"
  assert_equal "$2" "growl\""
  assert_equal "$3" "snap snap"
  assert_equal "$4" "-d"
}

@test "mixture of args  : integer values  : -a 1 -bc -d 2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -a 1 -bc -d 2
  assert_args 1 -b -c 2
}

@test "mixture of args  : string values   : -a:slurp -bc -d'bark bark'" {
  e2opt-names aardvark badger crocodile dingo
  e2opt -a:slurp -bc -d'bark bark'
  assert_args 'slurp' -b -c 'bark bark'
}

function assert_error() {
  output=""
  run e2opt "$@"
  assert_output -p "Error"
}

function assert_valid() {
  output=""
  run e2opt "$@"
  refute_output -p "Error"
}

@test "arg types        : int string bool '^(bark|woof)$'" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-validators int string bool '^(bark|woof)$'

  assert_valid -a5 -bgrowl --crocodile --dingo bark
  assert_error -aslurp -bgrowl --crocodile --dingo bark
  assert_error -a5 -b --crocodile --dingo bark
  assert_error -a5 -bgrowl --crocodile=snap --dingo bark
  assert_error -a5 -bgrowl --crocodile --dingo whine
  assert_valid -bgrowl --crocodile --dingo bark
  assert_valid -a5 --crocodile --dingo bark
  assert_valid -a5 -bgrowl --dingo bark
  assert_valid -a5 -bgrowl --crocodile
  assert_valid -a5 -b5 -c --dingo woof
}

@test "required + types" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-validators int string bool '^(bark|woof)$'
  e2opt-required true false or2 or2

  assert_valid -a5 -bgrowl --crocodile --dingo bark
  assert_error -aslurp -bgrowl --crocodile --dingo bark
  assert_error -a5 -b --crocodile --dingo bark
  assert_error -a5 -bgrowl --crocodile=snap --dingo bark
  assert_error -a5 -bgrowl --crocodile --dingo whine
  assert_error -bgrowl --crocodile --dingo bark
  assert_valid -a5 --crocodile --dingo bark
  assert_error -a5 -bgrowl
  assert_valid -a5 -bgrowl --crocodile
  assert_valid -a5 -b5 -c --dingo woof
}

@test "required args    : booleans        : true false true false" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required true false true false

  assert_error -a
  assert_error -ab
  assert_valid -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_valid -abc
  assert_error -abd
  assert_valid -acd
  assert_error -bcd
  assert_valid -abcd

  assert_valid -c --aardvark slurp -bgrowl
  assert_error -d --aardvark slurp -bgrowl
  assert_error -c= --aardvark slurp -bgrowl
  assert_error -c='' --aardvark slurp -bgrowl
  assert_error -c "" --aardvark slurp -bgrowl
  assert_valid -c "snap snap" --aardvark slurp -bgrowl
}

@test "required args    : and operator    : and false and true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required and false and true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_valid -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : and operator    : and false and2 and2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required and false and2 and2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : and operator    : and3 and4 and3 and4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required and3 and4 and3 and4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : and operator    : and11 and11 and11 and11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required and11 and11 and11 and11

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : or operator     : or false or true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required or false or true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_valid -ad
  assert_error -bc
  assert_error -bd
  assert_valid -cd
  assert_error -abc
  assert_valid -abd
  assert_valid -acd
  assert_valid -bcd
  assert_valid -abcd
}

@test "required args    : or operator     : or false or2 or2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required or false or2 or2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : or operator     : or3 or4 or3 or4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required or3 or4 or3 or4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_valid -ab
  assert_error -ac
  assert_valid -ad
  assert_valid -bc
  assert_error -bd
  assert_valid -cd
  assert_valid -abc
  assert_valid -abd
  assert_valid -acd
  assert_valid -bcd
  assert_valid -abcd
}

@test "required args    : or operator     : or11 or11 or11 or11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required or11 or11 or11 or11

  assert_valid -a
  assert_valid -b
  assert_valid -c
  assert_valid -d
  assert_valid -ab
  assert_valid -ac
  assert_valid -ad
  assert_valid -bc
  assert_valid -bd
  assert_valid -cd
  assert_valid -abc
  assert_valid -abd
  assert_valid -acd
  assert_valid -bcd
  assert_valid -abcd
}

@test "required args    : nand operator   : nand false nand true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nand false nand true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_valid -d
  assert_error -ab
  assert_error -ac
  assert_valid -ad
  assert_error -bc
  assert_valid -bd
  assert_valid -cd
  assert_error -abc
  assert_valid -abd
  assert_error -acd
  assert_valid -bcd
  assert_error -abcd
}

@test "required args    : nand operator   : nand false nand2 nand2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nand false nand2 nand2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : nand operator   : nand3 nand4 nand3 nand4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nand3 nand4 nand3 nand4

  assert_valid -a
  assert_valid -b
  assert_valid -c
  assert_valid -d
  assert_valid -ab
  assert_error -ac
  assert_valid -ad
  assert_valid -bc
  assert_error -bd
  assert_valid -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : nand operator   : nand11 nand11 nand11 nand11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nand11 nand11 nand11 nand11

  assert_valid -a
  assert_valid -b
  assert_valid -c
  assert_valid -d
  assert_valid -ab
  assert_valid -ac
  assert_valid -ad
  assert_valid -bc
  assert_valid -bd
  assert_valid -cd
  assert_valid -abc
  assert_valid -abd
  assert_valid -acd
  assert_valid -bcd
  assert_error -abcd
}

@test "required args    : nor operator    : nor false nor true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nor false nor true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_valid -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_valid -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : nor operator    : nor false nor2 nor2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nor false nor2 nor2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : nor operator    : nor3 nor4 nor3 nor4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nor3 nor4 nor3 nor4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : nor operator    : nor11 nor11 nor11 nor11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required nor11 nor11 nor11 nor11

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : xand operator   : xand false xand true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xand false xand true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_valid -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_valid -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_valid -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xand operator   : xand false xand2 xand2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xand false xand2 xand2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : xand operator   : xand3 xand4 xand3 xand4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xand3 xand4 xand3 xand4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_valid -ac
  assert_error -ad
  assert_error -bc
  assert_valid -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xand operator   : xand11 xand11 xand11 xand11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xand11 xand11 xand11 xand11

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xnor operator   : xnor false xnor true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xnor false xnor true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_valid -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_valid -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_valid -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xnor operator   : xnor false xnor2 xnor2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xnor false xnor2 xnor2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : xnor operator   : xnor3 xnor4 xnor3 xnor4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xnor3 xnor4 xnor3 xnor4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_valid -ac
  assert_error -ad
  assert_error -bc
  assert_valid -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xnor operator   : xnor11 xnor11 xnor11 xnor11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xnor11 xnor11 xnor11 xnor11

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_valid -abcd
}

@test "required args    : xor operator    : xor false xor true" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xor false xor true

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_valid -ad
  assert_error -bc
  assert_error -bd
  assert_valid -cd
  assert_error -abc
  assert_valid -abd
  assert_error -acd
  assert_valid -bcd
  assert_error -abcd
}

@test "required args    : xor operator    : xor false xor2 xor2" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xor false xor2 xor2

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_error -ab
  assert_error -ac
  assert_error -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : xor operator    : xor3 xor4 xor3 xor4" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xor3 xor4 xor3 xor4

  assert_error -a
  assert_error -b
  assert_error -c
  assert_error -d
  assert_valid -ab
  assert_error -ac
  assert_valid -ad
  assert_valid -bc
  assert_error -bd
  assert_valid -cd
  assert_error -abc
  assert_error -abd
  assert_error -acd
  assert_error -bcd
  assert_error -abcd
}

@test "required args    : xor operator    : xor11 xor11 xor11 xor11" {
  e2opt-names aardvark badger crocodile dingo
  e2opt-required xor11 xor11 xor11 xor11

  assert_valid -a
  assert_valid -b
  assert_valid -c
  assert_valid -d
  assert_valid -ab
  assert_valid -ac
  assert_valid -ad
  assert_valid -bc
  assert_valid -bd
  assert_valid -cd
  assert_valid -abc
  assert_valid -abd
  assert_valid -acd
  assert_valid -bcd
  assert_error -abcd
}
