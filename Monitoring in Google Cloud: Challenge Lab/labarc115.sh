#!/bin/bash

clear
# Welcome Banner
echo "╔════════════════════════════════════════════════════════╗"
echo "         CLOUD MONITORING CHALLENGE LAB TUTORIAL"
echo "╚════════════════════════════════════════════════════════╝"
echo
echo
echo "⚡ Initializing Cloud Monitoring Configuration..."
echo

# Section 1: Instance Configuration
echo "INSTANCE SETUP"
echo "Retrieving compute instance zone..."
export ZONE=$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)' | head -n 1)
echo " Zone: $ZONE "

echo "🆔 Fetching instance ID of apache-vm..."
INSTANCE_ID=$(gcloud compute instances describe apache-vm --zone=$ZONE --format='value(id)')
echo " Instance ID: $INSTANCE_ID "
echo

# Section 2: Monitoring Agent Setup
echo "MONITORING AGENT SETUP"
echo "Preparing monitoring agent installation script..."
cat > cp_disk.sh <<'EOF_CP'
curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
sudo bash add-logging-agent-repo.sh --also-install

curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
sudo bash add-monitoring-agent-repo.sh --also-install

(cd /etc/stackdriver/collectd.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/collectd.d/apache.conf)

sudo service stackdriver-agent restart
EOF_CP

echo "📤 Transferring script to apache-vm..."
gcloud compute scp cp_disk.sh apache-vm:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet
echo "✅ Script transferred successfully!"

echo "🚀 Executing script on apache-vm..."
gcloud compute ssh apache-vm --project=$DEVSHELL_PROJECT_ID --zone=$ZONE --quiet --command="bash /tmp/cp_disk.sh"
echo "✅ Monitoring agent setup completed!"
echo

# Section 3: Uptime Check
echo "UPTIME CHECK"
echo "Creating uptime check for the instance..."
gcloud monitoring uptime create arcadecrew \
  --resource-type="gce-instance" \
  --resource-labels=project_id=$DEVSHELL_PROJECT_ID,instance_id=$INSTANCE_ID,zone=$ZONE
echo "✅ Uptime check created successfully!"
echo

# Section 4: Notification Channel
echo "NOTIFICATION CHANNEL"
echo "Creating email notification channel..."
cat > email-channel.json <<EOF_CP
{
  "type": "email",
  "displayName": "arcadecrew",
  "description": "Arcade Crew",
  "labels": {
    "email_address": "$USER_EMAIL"
  }
}
EOF_CP

gcloud beta monitoring channels create --channel-content-from-file="email-channel.json"
echo "✅ Notification channel created!"
echo

# Section 5: Alert Policy
echo "ALERT POLICY"
echo "Creating alert policy..."
channel_info=$(gcloud beta monitoring channels list)
channel_id=$(echo "$channel_info" | grep -oP 'name: \K[^ ]+' | head -n 1)

cat > app-engine-error-percent-policy.json <<EOF_CP
{
  "displayName": "alert",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "VM Instance - Traffic",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"agent.googleapis.com/apache/traffic\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "crossSeriesReducer": "REDUCE_NONE",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "300s",
        "trigger": {
          "count": 1
        },
        "thresholdValue": 3072
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    "$channel_id"
  ],
  "severity": "SEVERITY_UNSPECIFIED"
}
EOF_CP

gcloud alpha monitoring policies create --policy-from-file="app-engine-error-percent-policy.json"
echo "Alert policy created successfully!"
echo

# Section 6: Quick Links
echo "QUICK LINKS"
echo "Dashboard: https://console.cloud.google.com/monitoring/dashboards?&project=$DEVSHELL_PROJECT_ID"
echo "Metrics: https://console.cloud.google.com/logs/metrics/edit?project=$DEVSHELL_PROJECT_ID"
echo

# Completion Banner
echo "╔════════════════════════════════════════════════════════╗"
echo "          LAB  COMPLETE!"
echo "╚════════════════════════════════════════════════════════╝"
echo
