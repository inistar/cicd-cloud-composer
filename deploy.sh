#!/bin/bash

# Make sure gcloud is in our path
PATH=$PATH:/usr/local/airflow/google-cloud-sdk/bin

# shellcheck disable=SC1091
source utils.sh

# Check to ensure all environment variables are set.
MISSING_REQ="false"
checkRequiredEnv
if [[ "$MISSING_REQ" == "true" ]]; then
  echo "Environment variables are missing."
  exit 1
fi

DAGNAME_REGEX=".+_dag_v[0-9]_[0-9]_[0-9]$"
DAG_LIST_FILE=${DAG_LIST_FILE:-running_dags.txt}
printStartingState

# Any default flags we want when using GCP SDK
GCLOUD="gcloud -q"
GSUTIL="gsutil -q"


echo "Authenticating service account..."
$GCLOUD auth activate-service-account "$SERVICE_ACCOUNT" \
  --key-file="$SA_KEY_LOCATION"

echo "Setting default gcloud project & composer location..."
$GCLOUD config set project "$PROJECT"
$GCLOUD config set composer/location "$REGION"

# Delete DAG from Airflow UI.
# $1 DAG id (string)
function wait_for_delete() {
  local status=1
  local limit=0
  while [ $status -eq 1 ]; do

    if [ $limit -eq 3 ]; then
        echo "Delete $1 is taking longer then $limit retries."
        exit 1
    fi

    echo "Deleting $1 from Airflow UI. Retry: $limit"
    $GCLOUD composer environments run "$ENVIRONMENT" \
      delete_dag -- "$1" && break
    status=$?

    limit=$((limit + 1))
    sleep 3
  done
}

# Unpause the DAG
# $1 DAG id (string)
function wait_for_deploy() {
  local status=1
  local limit=0

  while [[ $status -eq 1 ]]; do

    if [ $limit -eq 5 ]; then
        echo "Unpause $1 is taking longer then $limit retries."
        exit 1
    fi

    echo "Waiting for DAG deployment $1"

    $GCLOUD composer environments run "$ENVIRONMENT" unpause -- "$1" && break

    status=$?

    echo Retry: $limit. Return status: $status
    limit=$((limit+1))
    sleep 60
  done
}

# Pause DAG, delete file from GCS, and delete from Airflow UI. 
# $1 DAG id (string)
function handle_delete() {
  filename=$1.py

  echo "Pausing $1..."
  $GCLOUD composer environments run "$ENVIRONMENT" pause -- "$1"

  echo "Deleting $filename file..."
  $GCLOUD composer environments storage dags delete \
    --environment="$ENVIRONMENT" -- "$filename"
 
  wait_for_delete "$1"
}

# Add new files to GCS and unpause DAG.
# $1 DAG name (string)
function handle_new() {

  filename=$1.py

  echo "Uploading $filename file to composer..."
  $GCLOUD composer environments storage dags import \
    --environment="$ENVIRONMENT" \
    --source="$filename"

  deploy_start=$(date +%s)

  wait_for_deploy "$1"
  
  deploy_end=$(date +%s)
  runtime=$((deploy_end-deploy_start))

  echo "Wait for Deploy Runtime: " $runtime sec
}

# Get hash value of a file.
# $1 Path to local or GCS file. (string)
function gcs_md5() {
    gsutil hash "$1" | grep md5 | awk 'NF>1{print $NF}'
}

# Compare the hash values of two files. 
# $1 File path (string)
# $2 File path (string)
function validate_local_vs_gcs_dag_hashes() {
    if [[ "$(gcs_md5 "$1")" != "$(gcs_md5 "$2")" ]]; then
        echo "Error: The dag definition file: $1 did not match the \
          corresponding file in GCS Dags folder: $2"
        exit 1
    fi
}

# Get local and GCS file path and ensure, they are the same.
# $1 DAG file name (string)
function check_files_are_same(){

    local_file_path=$1.py
    gcs_file_path="gs://$BUCKET/dags/$1.py"

    validate_local_vs_gcs_dag_hashes "$local_file_path" "$gcs_file_path"
}

# Validate all DAGs in running_dags.txt file using local Airflow environment.
# $1 variables-ENV.json file (string)
function validate_dags_and_variables() {

  FERNET_KEY=$(python3.6 -c "from cryptography.fernet import Fernet; \
    print(Fernet.generate_key().decode('utf-8'))")

  export FERNET_KEY

  airflow initdb

  # Import Airflow Variables to local Airflow.
  echo "Uploading variables/$1"
  airflow variables --import variables/"$1"

  # Get current Cloud Composer custom connections.
  AIRFLOW_CONN_LIST=$($GCLOUD composer environments run "$ENVIRONMENT" \
    connections -- --list 2>&1 | grep "?\s" | awk '{ FS = "?"}; {print $2}' | \
    tr -d ' ' | sed -e "s/'//g" | grep -v '_default$' | \
    grep -v 'local_mysql' | tail -n +3 | grep -v "\.\.\.")

  echo "AIRFLOW_CONN_LIST: $AIRFLOW_CONN_LIST"

  # Upload custom connetions to local Airflow.
  for conn_id in $AIRFLOW_CONN_LIST; do
      echo "Uploading $conn_id..."
      airflow connections --add --conn_id "$conn_id" --conn_type http || \
        echo "Upload $conn_id to local Airflow failed"
  done

  RUNNING_DAGS=$(grep -iE "$DAGNAME_REGEX" < "$DAG_LIST_FILE")

  # Copy all RUNNING_DAGS to local Airflow dags folder for DAG validation.
  for dag_id in $RUNNING_DAGS; do
    echo "$dag_id".py
    cp "$dag_id".py /usr/local/airflow/dags
  done

  # List all DAGs running on local Airflow. 
  LOCAL_AIRFLOW_LIST_DAGS=$(airflow list_dags | sed -e '1,/DAGS/d' | \
    tail -n +2 | sed '/^[[:space:]]*$/d'| \
    grep -iE ".+_dag_v[0-9]_[0-9]_[0-9]$")

  echo "LOCAL_AIRFLOW_LIST_DAGS: $LOCAL_AIRFLOW_LIST_DAGS"

  # Run DAG validation tests. 
  python3.6 dag_validation_test.py "$LOCAL_AIRFLOW_LIST_DAGS"
}

# Upload and set Airflow variables. 
# $1 variables-ENV.json file (string)
function handle_variables() {
  echo "Uploading variables.json file to composer..."
  $GCLOUD composer environments storage data import \
    --source=variables/"$1" --environment="$ENVIRONMENT"

  echo "Setting Airflow variables in the composer environment..."
  $GCLOUD composer environments run "$ENVIRONMENT" \
    variables -- --i /home/airflow/gcs/data/"$1"
} 

# Upload Airflow Plugins.
function handle_plugins() {
    echo "Syncing plugins folder..."
    $GSUTIL rsync -r -d plugins/ gs://"$BUCKET"/plugins/ || \
      echo "Upload plugins failed"
}

# Outputs the list of DAGs that need to started and stopped.
function get-stop-and-start-dags() {
    echo "Getting running dags..."

    RUNNING_DAGS=$($GCLOUD composer environments run "$ENVIRONMENT" \
    --location "$REGION" list_dags 2>&1 | sed -e '1,/DAGS/d' | \
    tail -n +2 | sed '/^[[:space:]]*$/d'| grep -iE "$DAGNAME_REGEX" )

    echo "Got RUNNING_DAGS = ${RUNNING_DAGS}"

    echo "Deciding which dags to start/stop..."
    # shellcheck disable=SC2002
    DAGS_TO_RUN=$(cat "$DAG_LIST_FILE" | grep -iE "$DAGNAME_REGEX" )

    echo "DAGS_TO_RUN = ${DAGS_TO_RUN}"

    DAGS_TO_STOP=$(arrayDiff "${RUNNING_DAGS[@]}" "${DAGS_TO_RUN[@]}")
    DAGS_TO_START=$(arrayDiff "${DAGS_TO_RUN[@]}" "${RUNNING_DAGS[@]}")
    SAME_DAG=$(arraySame "${RUNNING_DAGS[@]}" "${DAGS_TO_RUN[@]}")

    for dag_id in $SAME_DAG; do
        echo "Checking $dag_id hash values."
        check_files_are_same "$dag_id"
    done

    # TODO: remove me when updating to Spinnaker 1.16
    # See https://github.com/spinnaker/spinnaker/issues/4629
    echo "SPINNAKER_PROPERTY_FOO=bar"

    if [ -n "$DAGS_TO_STOP" ]; then
      echo "SPINNAKER_PROPERTY_DAGS_TO_STOP=${DAGS_TO_STOP// /,}"
    fi

    if [ -n "$DAGS_TO_START" ]; then
      echo "SPINNAKER_PROPERTY_DAGS_TO_START=${DAGS_TO_START// /,}"
    fi
}

case "$1" in
    get-stop-and-start-dags)
        get-stop-and-start-dags || \
          { echo "get-stop-and-start-dags failed"; exit 1; }
        ;;
    stop-dag)
        if [[ -z "$2" ]]; then
          echo "Not given any dags to stop, so exiting."
          exit 0
        fi

        $GSUTIL stat gs://"$BUCKET"/dags/"$2".py
        if [[ $? -eq 1 ]]; then
          echo "GCS File gs://$BUCKET/dags/$2.py not found!"
          exit 1
        fi

        echo "Processing $2..."
        handle_delete "$2" || { echo "handle_delete failed"; exit 1; }
        ;;
    upload-plugins-and-variables)
        if [[ -z "$2" ]]; then
          echo "Not given any arguments, so exiting."
          exit 0
        elif [ ! -f "variables/$2" ]; then
          echo "File variables/$2 not found!"
          exit 1
        fi

        validate_dags_and_variables "$2"  || \
          { echo "validate_dags_and_variables failed"; exit 1; }

        handle_variables "$2" || { echo "handle_variables failed"; exit 1; }
        handle_plugins || { echo "handle_plugins failed"; exit 1; }
        ;;
    start-dag)
        if [[ -z "$2" ]]; then
          echo "Not given any dags to start, so exiting."
          exit 0
        elif [ ! -f "$2".py ]; then
          echo "File $2.py not found!"
          exit 1
        fi

        echo "Processing $2..."
        handle_new "$2" || { echo "handle_new failed"; exit 1; }
        ;;
    *)
        echo "Usage: $1 is not valid. { get-stop-and-start-dags | \
          stop-dag | upload-plugins-and-variables | start-dag }"
        exit 1
        ;;
esac
