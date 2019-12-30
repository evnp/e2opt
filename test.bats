#!/usr/bin/env bash

load './node_modules/bats-support/load'
load './node_modules/bats-assert/load'

source $BATS_TEST_DIRNAME/e2args

function assert_args() {
  local expected=( "$@" )

  # numArgs: max length between ARGS and expected arrays
  local numArgs="${#ARGS[@]}"
  (( "${#expected[@]}" > numArgs )) && numArgs="${#expected[@]}"

  local i
  for (( i = 0 ; i < numArgs ; i++ )); do
    assert_equal "${ARGS[${i}]}" "${expected[${i}]}"
  done
}

@test "boolean flag args : basic           : -a -b -c -d" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -a -b -c -d
  assert_args -a -b -c -d
}

@test "boolean flag args : arbitrary order : -c -a -d -b" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -c -a -d -b
  assert_args -a -b -c -d
}

@test "boolean flag args : shorthand       : -acd -b" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -acd -b
  assert_args -a -b -c -d
}

@test "key/value args    : basic           : -a1 -b=2 -c:3 -d 4" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -a1 -b=2 -c:3 -d 4
  assert_args 1 2 3 4
}

@test "key/value args    : arbitrary order : -c:3 -a1 -d 4 -b=2" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -c:3 -a1 -d 4 -b=2
  assert_args 1 2 3 4
}

@test "key/value args    : string values   : -c:'snap snap' -aslurp -d 'bark bark' -b=" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -c:'snap snap' -aslurp -d 'bark bark' -b=
  assert_args 'slurp' '' 'snap snap' 'bark bark'
}

@test "key/value args    : empty values    : -c:'' -a= -d \"\" -b=\"\"" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -c:'' -a= -d "" -b=""
  assert_args '' '' '' ''
}

@test "key/value args    : quotes" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -c:'' -a= -d "'single'" -b="\"double\""
  assert_args '' "\"double\"" '' "'single'"
}

@test "longform args     : integer values  : --aardvark -c 1 --badger 2 --dingo" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args --aardvark -c 1 --badger 2 --dingo
  assert_args -a 2 1 -d
}

@test "longform args    : string values   : --aardvark -c 'snap snap' --badgergrowl -d" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args --aardvark -c 'snap snap' --badgergrowl -d
  assert_args -a growl 'snap snap' -d
}

@test "longform args    : empty values    : --aardvark -c '' --badger:\"\" --dingo=''" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args --aardvark -c '' --badger:"" --dingo=
  assert_args -a '' '' ''
}

@test "longform args    : quotes" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args --aardvark -c "'single'" --badger:"\"double\"" --dingo=
  assert_args -a "\"double\"" "'single'" ''
}

@test "mixture of args  : integer values  : -a 1 -bc -d 2" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -a 1 -bc -d 2
  assert_args 1 -b -c 2
}

@test "mixture of args  : string values   : -a:slurp -bc -d'bark bark'" {
  local ARGS=(aardvark badger crocodile dingo)
  e2args -a:slurp -bc -d'bark bark'
  assert_args 'slurp' -b -c 'bark bark'
}

function assert_error() {
  output=""
  run e2args "$@"
  assert_output -p "Error"
}

function assert_valid() {
  output=""
  run e2args "$@"
  refute_output -p "Error"
}

@test "required args    : true false true false" {
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_REQUIRED=(true false true false)

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

@test "required args    : or false or true" {
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_REQUIRED=(or false or true)

  assert_error -a
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

  assert_valid -c -bgrowl --dingo bark
  assert_error -bgrowl --dingo bark
  assert_error -c= -bgrowl --dingo bark
  assert_error -c='' -bgrowl --dingo bark
  assert_error -c "" -bgrowl --dingo bark
  assert_valid -c "snap snap" -bgrowl --dingo bark
}

@test "required args    : 3 false 2 2" {
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_REQUIRED=(3 false 2 2)

  assert_error -a
  assert_error -ab
  assert_valid -ac
  assert_valid -ad
  assert_error -bc
  assert_error -bd
  assert_error -cd
  assert_valid -abc
  assert_valid -abd
  assert_valid -acd
  assert_error -bcd
  assert_valid -abcd

  assert_valid --aardvark -c -bgrowl
  assert_error --aardvark -bgrowl
  assert_error --aardvark -c= -bgrowl
  assert_error --aardvark -c='' -bgrowl
  assert_error --aardvark -c "" -bgrowl
  assert_valid --aardvark -c "snap snap"
}

@test "required args    : 3 4 3 4" {
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_REQUIRED=(3 4 3 4)

  assert_error -a
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

  assert_valid -c -bgrowl --dingo bark
  assert_error -bgrowl --dingo bark
  assert_error -c= -bgrowl --dingo bark
  assert_error -c='' -bgrowl --dingo bark
  assert_error -c "" -bgrowl --dingo bark
  assert_valid -c "snap snap" -bgrowl --dingo bark
}

@test "arg types        : int string bool '^(bark|woof)$'" {
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_VALIDATORS=(int string bool '^(bark|woof)$')

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
  local ARGS=(aardvark badger crocodile dingo)
  local ARGS_VALIDATORS=(int string bool '^(bark|woof)$')
  local ARGS_REQUIRED=(3 false 2 2)

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
