import boto3, os, json
from botocore.exceptions import ClientError, WaiterError

AWS_REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
ec2 = boto3.client("ec2", region_name=AWS_REGION)
sns = boto3.client("sns", region_name=AWS_REGION)

INSTANCE_ID = os.environ.get("INSTANCE_ID", "").strip()
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "").strip()
WEBHOOK_TOKEN = os.environ.get("WEBHOOK_TOKEN", "").strip()

def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": {"Content-Type": "application/json"}, "body": json.dumps(body)}

def _get_header(headers: dict, key: str) -> str:
    if not headers:
        return ""
    for k, v in headers.items():
        if k.lower() == key.lower():
            return v
    return ""

def _describe(instance_id: str) -> dict:
    r = ec2.describe_instances(InstanceIds=[instance_id])
    inst = r["Reservations"][0]["Instances"][0]
    return {
        "state": inst["State"]["Name"],
        "instance_type": inst.get("InstanceType"),
        "az": inst.get("Placement", {}).get("AvailabilityZone"),
        "launch_time": inst.get("LaunchTime").isoformat() if inst.get("LaunchTime") else None,
        "private_ip": inst.get("PrivateIpAddress"),
        "public_ip": inst.get("PublicIpAddress"),
    }

def _status_checks(instance_id: str) -> dict:
    r = ec2.describe_instance_status(InstanceIds=[instance_id], IncludeAllInstances=True)
    if not r["InstanceStatuses"]:
        return {"system": "unknown", "instance": "unknown"}
    s = r["InstanceStatuses"][0]
    return {
        "system": s["SystemStatus"]["Status"],
        "instance": s["InstanceStatus"]["Status"],
    }

def lambda_handler(event, context):
    if not INSTANCE_ID:
        return _response(500, {"ok": False, "error": "Missing INSTANCE_ID"})

    headers = event.get("headers", {}) if isinstance(event, dict) else {}
    if WEBHOOK_TOKEN:
        token = _get_header(headers, "X-Webhook-Token")
        if token != WEBHOOK_TOKEN:
            return _response(401, {"ok": False, "error": "Unauthorized"})

    try:
        before = _describe(INSTANCE_ID)
        before_checks = _status_checks(INSTANCE_ID)

        ec2.reboot_instances(InstanceIds=[INSTANCE_ID])

        # Wait until both status checks pass (real “healthy” signal)
        waiter = ec2.get_waiter("instance_status_ok")
        waiter.wait(
            InstanceIds=[INSTANCE_ID],
            WaiterConfig={"Delay": 10, "MaxAttempts": 60}
        )

        after = _describe(INSTANCE_ID)
        after_checks = _status_checks(INSTANCE_ID)

        if SNS_TOPIC_ARN:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject="EC2 Reboot: status checks OK",
                Message=f"EC2 {INSTANCE_ID} rebooted and passed status checks in {AWS_REGION}."
            )

        return _response(200, {
            "ok": True,
            "action": "reboot",
            "region": AWS_REGION,
            "instance_id": INSTANCE_ID,
            "before": {"describe": before, "checks": before_checks},
            "after": {"describe": after, "checks": after_checks},
        })

    except WaiterError as e:
        # Reboot requested but instance never became healthy in time
        after = {}
        after_checks = {}
        try:
            after = _describe(INSTANCE_ID)
            after_checks = _status_checks(INSTANCE_ID)
        except Exception:
            pass

        return _response(504, {
            "ok": False,
            "error": "Timed out waiting for instance_status_ok",
            "region": AWS_REGION,
            "instance_id": INSTANCE_ID,
            "after": {"describe": after, "checks": after_checks},
            "details": str(e),
        })

    except ClientError as e:
        return _response(500, {"ok": False, "error": str(e), "region": AWS_REGION, "instance_id": INSTANCE_ID})
    except Exception as e:
        return _response(500, {"ok": False, "error": str(e), "region": AWS_REGION, "instance_id": INSTANCE_ID})
