{
  "Comment": "Break-glass weight flip for warehouse.example.com, at the apex of its own private hosted zone. Render with envsubst.",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "warehouse.example.com",
        "Type": "A",
        "SetIdentifier": "onprem",
        "Weight": ${ONPREM_WEIGHT},
        "TTL": 60,
        "ResourceRecords": [{ "Value": "203.0.113.10" }]
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "warehouse.example.com",
        "Type": "A",
        "SetIdentifier": "aws",
        "Weight": ${AWS_WEIGHT},
        "AliasTarget": {
          "HostedZoneId": "${ALB_ZONE_ID}",
          "DNSName": "${ALB_DNS_NAME}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
