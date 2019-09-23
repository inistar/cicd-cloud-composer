# cicd-cloud-composer
Repo contains sample code for deploying DAGs to Google Cloud Composer, dockerfile, and DAG validation.


## Deploy Script
#### Deploy Options

| Option Name | Positional Arguments | Description |
|------|-------------|----|
| get-stop-and-start-dags | n/a | Outputs a list of all the DAG ids that need to be started and stopped. |
| stop-dag | example_dag_4_v1_1_1 | Removes the specified DAG id from the Cloud Composer environment. |
| upload-plugins-and-variables | n/a | Uploads plugins and Airflow variables. |
| start-dag | example_dag_2_v1_1_1 | Adds the specified DAG id to the Cloud Composer.


#### Helper Functions
| Function Name | Description | Parameters |
|------|-------------|-----|
| get-stop-and-start-dags | Outputs the list of DAGs that need to started and stopped. | n/a |
| handle_delete | Pause DAG, delete file from GCS, and delete from Airflow UI. | $1 DAG id |
| handle_new | Add new files to GCS and unpause DAG. | $1 DAG id |
| handle_variables | Upload and set Airflow variables. | n/a |
| handle_plugins | Upload Airflow Plugins. | n/a |
| wait_for_delete | Delete DAG from Airflow UI. | $1 DAG id |
| wait_for_deploy | Unpause the DAG. | $1 DAG id |
| validate_dags_and_variables | Validate all DAGs in running_dags.txt file using local Airflow environment. | $1 vairables-ENV.json|
| check_files_are_same | Get local and GCS file path and ensure, they are the same. | $1 DAG file name |
| validate_local_vs_gcs_dag_hashes | Compare the hash value of a file | $1 and $2 file path |
| gcs_md5 | Get hash value of a file | $1 file path |
