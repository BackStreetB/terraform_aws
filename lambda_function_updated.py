import boto3
import os
import time
import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    logger.info("Lambda triggered. Full event: %s", json.dumps(event))
    instance_id = os.environ.get('INSTANCE_IDS')
    if not instance_id:
        logger.error("INSTANCE_IDS environment variable is missing.")
        return {"statusCode": 500, "body": "Missing INSTANCE_IDS env var"}

    ec2 = boto3.client('ec2')
    ssm = boto3.client('ssm')

    try:
        if "Records" in event and "Sns" in event["Records"][0]:
            sns_message = event["Records"][0]["Sns"]["Message"]
            logger.info("SNS Message: %s", sns_message)
        else:
            logger.warning("Event không đến từ SNS hoặc sai định dạng.")

        instance = ec2.describe_instances(InstanceIds=[instance_id])["Reservations"][0]["Instances"][0]
        launch_time = instance["LaunchTime"]
        uptime = datetime.now(timezone.utc) - launch_time
        if uptime.total_seconds() < 180:
            logger.warning("🕑 Instance just started, skipping reboot to avoid false positive.")
            return {"statusCode": 200, "body": "Instance too new. Skipping restart."}

        logger.info(f"Attempting to restart NGINX on EC2 instance {instance_id} via SSM...")
        response = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName="AWS-RunShellScript",
            Parameters={'commands': [
                'sudo systemctl restart nginx',
                'sleep 5',
                'sudo systemctl is-active nginx'
            ]}
        )
        command_id = response['Command']['CommandId']

        for i in range(3):
            time.sleep(5)
            output = ssm.get_command_invocation(CommandId=command_id, InstanceId=instance_id)
            logger.info(f"Attempt {i+1}: NGINX status output: {output['StandardOutputContent']}")
            if output['Status'] == 'Success' and 'active' in output['StandardOutputContent']:
                logger.info("✅ Successfully restarted NGINX")
                return {"statusCode": 200, "body": json.dumps({
                    "message": "NGINX restarted successfully", "action": "nginx_restart"
                })}

        logger.warning("❌ All restart attempts failed. Rebooting...")
        return reboot_instance(ec2, instance_id)

    except Exception as e:
        logger.error("❌ Lambda error: %s", str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'message': f'Lambda error: {str(e)}', 'action': 'lambda_error'})
        }

def reboot_instance(ec2, instance_id):
    try:
        logger.info(f"🔄 Stopping instance {instance_id}")
        ec2.stop_instances(InstanceIds=[instance_id])
        ec2.get_waiter('instance_stopped').wait(InstanceIds=[instance_id])
        logger.info(f"✅ Stopped. Now starting instance {instance_id}")
        ec2.start_instances(InstanceIds=[instance_id])
        ec2.get_waiter('instance_running').wait(InstanceIds=[instance_id])
        logger.info(f"✅ Successfully rebooted instance {instance_id}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully rebooted instance {instance_id}',
                'action': 'instance_reboot'
            })
        }
    except Exception as e:
        logger.error(f"❌ Reboot failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'message': f'Error rebooting instance: {str(e)}', 'action': 'reboot_error'})
        }