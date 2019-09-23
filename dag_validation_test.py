import os
import re
import sys
import time
import unittest

from airflow.models import DagBag
from airflow.models import Variable


class TestDagIntegrity(unittest.TestCase):
    
    LOAD_SECOND_THRESHOLD = 2
    LOCAL_DAG_IDS = None

    def setUp(self):
        self.dagbag = DagBag()
        self.LOCAL_DAG_IDS = self.LOCAL_DAG_IDS.split("\n")
    

    def test_import_dags(self):
        print("Running test_import_dags")
        self.assertFalse(
            len(self.dagbag.import_errors),
            'DAG import failures. Errors: {}'.format(
                self.dagbag.import_errors
            )
        )
    
    def test_same_file_and_dag_id_name(self):
        print("Running test_same_file_and_dag_id_name")

        file_dag_ids = []

        files = [f for f in os.listdir('.') if os.path.isfile(f)]
        for file_name in files:

            result = re.search(r'.+_dag_v[0-9]_[0-9]_[0-9].py', file_name, re.I)

            if (result != None):
                file_dag_id = result.group().replace(".py", "")
                
                file_dag_ids.append(file_dag_id)
        
        for dag_id in self.LOCAL_DAG_IDS:
            self.assertTrue(dag_id in self.LOCAL_DAG_IDS)

    def test_import_time(self):
        print("Running test_import_time")
        fp = open("running_dags.txt", "r")

        for dag_id in fp:
            start = time.time()

            dag_file = dag_id + ".py"
            self.dagbag.process_file(dag_file)

            end = time.time()
            total = end - start

            print("Total Time:", total)

            self.assertLessEqual(total, self.LOAD_SECOND_THRESHOLD)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        TestDagIntegrity.LOCAL_DAG_IDS = sys.argv.pop()

    unittest.main()