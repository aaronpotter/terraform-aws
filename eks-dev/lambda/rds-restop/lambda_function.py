import os
import time

import boto3

rds = boto3.client("rds")
DB_ID = os.environ["DB_INSTANCE_ID"]


def lambda_handler(event, context):
    # RDS restarts a stopped instance after 7 days. Wait for it to come up, then stop it again.
    # StopDBInstance is rejected while the instance is still "starting".
    while True:
        status = rds.describe_db_instances(DBInstanceIdentifier=DB_ID)["DBInstances"][0]["DBInstanceStatus"]
        if status == "available":
            rds.stop_db_instance(DBInstanceIdentifier=DB_ID)
            return f"stopping {DB_ID}"
        if status in ("stopped", "stopping"):
            return f"{DB_ID} already {status}"
        if context.get_remaining_time_in_millis() < 40000:
            raise RuntimeError(f"{DB_ID} still {status}; giving up")
        time.sleep(20)
