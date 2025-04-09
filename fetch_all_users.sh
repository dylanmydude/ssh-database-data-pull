#!/bin/bash

source ./db_config.env

read -s -p "Enter $CHIRP_USER DB password: " CHIRP_PW
echo

OUTPUT="all_users.csv"
LOGFILE="failures.log"

echo "site,username,first_name,last_name,email,mobile,last_sign_in_at" > "$OUTPUT"
echo "=== Failed Connections or Queries ===" > "$LOGFILE"

SITES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SITES+=("$line")
done < "sites.txt"

for SITE in "${SITES[@]}"; do
  echo "🔄 Connecting to $SITE..."

  ssh -t -o ConnectTimeout=10 -o ConnectionAttempts=1 deploy@$SITE "
    psql -h localhost -U $IOTCORE_USER -d $IOTCORE_DB \
    -c \"\\copy (SELECT username, first_name, last_name, email, mobile, last_sign_in_at FROM users) TO STDOUT WITH CSV HEADER;\"
  " > tmp_users.csv 2>/dev/null

  if [ $? -ne 0 ] || [ $(wc -l < tmp_users.csv) -le 1 ]; then
    ssh -t -o ConnectTimeout=10 -o ConnectionAttempts=1 deploy@$SITE "
      PGPASSWORD='$CHIRP_PW' psql -h localhost -U $CHIRP_USER -d $CHIRP_DB \
      -c \"\\copy (SELECT username, first_name, last_name, email, '' AS mobile, last_sign_in_at FROM users) TO STDOUT WITH CSV HEADER;\"
    " > tmp_users.csv 2>/dev/null
  fi

  if [ $(wc -l < tmp_users.csv) -gt 1 ]; then
    echo "✅ Data received from $SITE"
    tail -n +2 tmp_users.csv | awk -v site="$SITE" -F',' 'BEGIN{OFS=","} {print site, $1, $2, $3, $4, $5, $6}' >> "$OUTPUT"
  else
    echo "❌ $SITE - FAILED"
    echo "$SITE - FAILED" >> "$LOGFILE"
  fi
done

rm -f tmp_users.csv

echo -e "\n✅ All done."
echo "📄 Data saved to: $OUTPUT"
echo "⚠️ Failures logged to: $LOGFILE"
