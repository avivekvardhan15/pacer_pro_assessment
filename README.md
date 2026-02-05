# pacer_pro_assessment
Create a monitoring and automation solution that helps identify and resolve these issues automatically.

Architecture (What we’re building)

Goal: Detect slow API responses in logs and trigger an automated remediation + notification.

Flow:
1. Flask app runs on EC2 and writes JSON logs to a local file ('app.log').
2. Sumo Logic Installed Collector tails 'app.log' via a Local File Source.
3. Sumo Search query finds '/api/data' calls where response time > 3 seconds.
4. An Alert / Scheduled Search triggers when **> 5 slow events in a 10-minute window.
5. Alert fires a Webhook to an AWS Lambda Function URL (or API Gateway).
6. Lambda **reboots** the EC2 instance and publishes an SNS email notification.


Flask application running commands for requests:

curl -i -X POST http://<ip-address>:8080/api/slow-mode/enable
curl -i -X POST http://<ip-address>:8080/api/data
for i in $(seq 1 50); do   curl -s -o /dev/null -w "%{http_code}\n" http://<ip-address>:8080/health;   sleep 3.6; done

Sumologic connection from local terminal for a service:

sudo ./SumoCollector_linux_amd64_19_534-2.sh

Terraform comands:

terraform init
terraform apply
terraform output
