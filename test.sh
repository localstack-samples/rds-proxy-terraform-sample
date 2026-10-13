#!/bin/bash
# Initialize the database, then walk a dog through the API:
# POST (secret auth through the RDS proxy), GET (RDS Data API),
# PUT (IAM auth token through the IAM proxy), DELETE (secret from Secrets Manager).
set -euo pipefail

TF_DIR=${TF_DIR:-terraform}
NAME="ci-dog-$(date +%s)"
OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

for fn in post-dog put-dog delete-dog db-setup; do
  host=$(lstk aws lambda get-function-configuration --function-name "$fn" \
    --query 'Environment.Variables.HOST || Environment.Variables.RDS_PROXY_ENDPOINT' --output text)
  if [ -z "$host" ] || [ "$host" = "None" ]; then
    echo "Test failed: $fn has no proxy endpoint set. Run 'lstk tf apply --auto-approve' again."
    exit 1
  fi
done

lstk aws lambda invoke --function-name db-setup --cli-read-timeout 120 "$OUT" > /dev/null
if ! jq -e '.statusCode == 200' "$OUT" > /dev/null; then
  echo "Test failed: db-setup returned $(cat "$OUT")"
  exit 1
fi
echo "PASS: db-setup created the dogs table"

API="$(cd "$TF_DIR" && lstk tf output -raw api_gateway_url)/dev/dogs"
echo "API: $API"

# request <expected status> <expected body substring> <curl args...>
request() {
  local status=$1 substring=$2 response actual
  shift 2
  response=$(curl -s -m 60 -w '\n%{http_code}' -H 'Content-Type: application/json' "$@")
  actual=${response##*$'\n'}
  response=${response%$'\n'*}
  if [ "$actual" != "$status" ] || [[ "$response" != *"$substring"* ]]; then
    echo "Test failed: $* returned HTTP $actual '$response', expected $status with '$substring'" >&2
    return 1
  fi
  echo "$response"
}

request 200 "Dog added successfully!" -X POST "$API" \
  -d "{\"name\": \"$NAME\", \"age\": \"1\", \"category\": \"Pupper\"}" > /dev/null
echo "PASS: POST added $NAME through the secret auth proxy"

CLUSTER_ARN=$(lstk aws rds describe-db-clusters --db-cluster-identifier dogdb-cluster \
  --query 'DBClusters[0].DBClusterArn' --output text)
SECRET_ARN=$(lstk aws secretsmanager describe-secret --secret-id super-secret --query ARN --output text)
ID=$(lstk aws rds-data execute-statement --resource-arn "$CLUSTER_ARN" --secret-arn "$SECRET_ARN" \
  --database dogs --sql "SELECT id FROM dogs WHERE name = :name" \
  --parameters "[{\"name\": \"name\", \"value\": {\"stringValue\": \"$NAME\"}}]" \
  --query 'records[0][0].longValue' --output text)
echo "Dog id: $ID"

dog=$(request 200 "$NAME" "$API/$ID")
if ! echo "$dog" | jq -e --arg n "$NAME" '.name == $n and .age == 1 and .category == "Pupper"' > /dev/null; then
  echo "Test failed: GET returned $dog"
  exit 1
fi
echo "PASS: GET returned the dog through the RDS Data API"

request 200 "Dog updated successfully!" -X PUT "$API" \
  -d "{\"id\": \"$ID\", \"name\": \"$NAME\", \"age\": \"2\", \"category\": \"Woofer\"}" > /dev/null
dog=$(request 200 "$NAME" "$API/$ID")
if ! echo "$dog" | jq -e '.age == 2 and .category == "Woofer"' > /dev/null; then
  echo "Test failed: GET after PUT returned $dog"
  exit 1
fi
echo "PASS: PUT updated the dog through the IAM auth proxy"

request 200 "Dog deleted successfully!" -X DELETE "$API/$ID" > /dev/null
request 404 "Dog not found" "$API/$ID" > /dev/null
echo "PASS: DELETE removed the dog"

echo "Test passed: the dog API works through both RDS proxies"
