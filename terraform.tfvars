aws_region    = "us-east-2"
key_pair_name = "test_key"
sns_email     = "avivekvardhan15@gmail.com"

sumo_api_base           = "https://api.sumologic.com"
sumo_installation_token = "U1VNT0dpWFAzRk90bnVEUEZLczZVZ3FzRGtBc1NEVWpodHRwczovL2NvbGxlY3RvcnMuc3Vtb2xvZ2ljLmNvbQ=="
collector_name          = "sampleapp-ec2-collector"
sumo_access_id          = "sujGSAfL6ueCeg"
sumo_access_key         = "V2bb1gAc9xp6D98khtfYPWEF9IYfV299m7piiXm4qAFVhXzVQZ7mxTW5nbos7RFa"

sumo_query = <<EOT
_sourceCategory=prod/flask/app1
| json auto
| where path="/api/data" and toLong(response_time_ms) > 3000
| timeslice 10m
| count as slow_events by _timeslice
| where slow_events >= 5
EOT

lookback_minutes = 15
