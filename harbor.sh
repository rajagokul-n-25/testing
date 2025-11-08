#!/bin/bash
# -----------------------------------------
# Harbor Cleanup Script (multi-repo support)
# Pass REPO name as argument or environment variable
# -----------------------------------------

# Harbor credentials and project details
HARBOR_USER="your_username"
HARBOR_PASSWORD="your_password"
HARBOR_URL="https://harbor.example.com"
PROJECT="your_project"

# Repository name (passed via ENV or argument)
REPO="${REPO:-$1}"

if [ -z "$REPO" ]; then
  echo "❌ Error: Repository name not provided."
  echo "Usage: REPO=myrepo ./harbor_cleanup.sh"
  echo "   or  ./harbor_cleanup.sh myrepo"
  exit 1
fi

# Cleanup threshold
THRESHOLD_DATE=$(date -d "3 days ago" --iso-8601=seconds)

TOTAL_DELETED=0
echo "===== Harbor Cleanup Started for $PROJECT/$REPO at $(date) ====="

# Fetch artifacts
RESPONSE=$(curl -s -u "$HARBOR_USER:$HARBOR_PASSWORD" \
  "$HARBOR_URL/api/v2.0/projects/$PROJECT/repositories/$REPO/artifacts?page_size=1000")

COUNT=$(echo "$RESPONSE" | jq 'length')
echo "Total artifacts found: $COUNT"

TO_DELETE=$(echo "$RESPONSE" | jq -r --arg threshold "$THRESHOLD_DATE" '
  .[]
  | select(.push_time < $threshold)
  | select((.tags | map(.name) | index("latest")) | not)
  | .digest' | wc -l)

echo "Artifacts to delete: $TO_DELETE"

# Delete eligible artifacts
echo "$RESPONSE" | jq -r --arg threshold "$THRESHOLD_DATE" '
  .[]
  | select(.push_time < $threshold)
  | select((.tags | map(.name) | index("latest")) | not)
  | "\(.push_time) \(.digest) \(.tags | map(.name) | join(","))"' \
| while read -r push_time digest tags; do
    echo "Deleting artifact: digest=$digest, pushed at=$push_time, tags=[$tags]"
    curl -s -X DELETE -u "$HARBOR_USER:$HARBOR_PASSWORD" \
      "$HARBOR_URL/api/v2.0/projects/$PROJECT/repositories/$REPO/artifacts/$digest" > /dev/null
    ((TOTAL_DELETED++))
done

echo "Total artifacts deleted: $TOTAL_DELETED"

# Trigger Harbor GC
echo "Triggering Harbor garbage collection..."
curl -s -X POST -u "$HARBOR_USER:$HARBOR_PASSWORD" "$HARBOR_URL/api/v2.0/system/gc"
echo "Garbage collection job started. Monitor via Harbor UI or API."

# --- Log Retention Policy ---
LOG_DIR="/opt/logs"
RETENTION_DAYS=60

find "$LOG_DIR" -type f -name "harbor_cleanup_${REPO}_*.log" -mtime +$RETENTION_DAYS -exec rm -f {} \;
echo "Old log files older than $RETENTION_DAYS days have been removed from $LOG_DIR."

echo "===== Harbor Cleanup Completed for $PROJECT/$REPO at $(date) ====="



0 2 */15 * * REPO=frontend /opt/scripts/harbor_cleanup.sh >> /opt/logs/harbor_cleanup_frontend_$(date +\%Y-\%m-\%d).log 2>&1

