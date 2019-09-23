#!/bin/bash

function checkRequiredEnv {
  if [[ -z $PROJECT ]]; then
    echo "PROJECT env variable is required, but unset."
    MISSING_REQ="true"
  fi

  if [[ -z $ENVIRONMENT ]]; then
    echo "ENVIRONMENT env variable is required, but unset."
    MISSING_REQ="true"
  fi

  if [[ -z $BUCKET ]]; then
    echo "BUCKET env variable is required, but unset."
    MISSING_REQ="true"
  fi

  if [[ -z $REGION ]]; then
    echo "REGION env variable is required, but unset."
    MISSING_REQ="true"
  fi

  if [[ -z $SA_KEY_LOCATION ]]; then
    echo "SA_KEY_LOCATION env variable is required, but unset."
    MISSING_REQ="true"
  fi

  if [ ! "$(command -v gcloud)" ]; then
    echo "gcloud is missing."
    MISSING_REQ="true"
  fi

  if [ ! "$(command -v gsutil)" ]; then
    echo "gsutil is missing."
		# shellcheck disable=SC2034
    MISSING_REQ="true"
  fi
}

function printStartingState {
  echo -e "Starting deploy script with:\\n\
    DAG_LIST_FILE = ${DAG_LIST_FILE} \\n\
    PROJECT = ${PROJECT} \\n\
    ENVIRONMENT = ${ENVIRONMENT} \\n\
    BUCKET = ${BUCKET} \\n\
    REGION = ${REGION} \\n\
    SA_KEY_LOCATION = ${SA_KEY_LOCATION}"
}

# Get the last element from the file path.
# $1 file_path (string)
function last_element() {
  echo "$1" | grep -oE "[^/]+$"
}

# Get only the file name without the extension
# $1 file_path (string)
function only_file_name() {
  echo "$1" | grep -oE "[^/]+$" | grep -oE "^([^.]+)"
}

# Filter by expression
# $1 input (string)
# $2 filter expression (regex pattern)
function filter() {
  echo "$1" | grep "$2"
}

function arrayDiff(){
    local result=()
    local array1=$1
    local array2=$2

    while read -r a1 ; do
      found=False
      
      while read -r a2 ; do
        if [[ $a1 == $a2 ]]; then
          found=True
          break
        fi
      done <<< "$array2"

      if [[ "$found" == "False" ]]; then
        result+=("$a1")
      fi
      
    done <<< "$array1"

    echo "${result[@]}"
}

function arraySame(){
    local result=()
    local array1=$1
    local array2=$2

    while read -r a1 ; do

        while read -r a2 ; do
            if [[ $a1 == $a2 ]]; then
              result+=("$a1")
              break
            fi
        done <<< "$array2"

    done <<< "$array1"

    echo "${result[@]}"
}
