#!/bin/bash

dnf update -y
dnf install -y docker aws-cli python3 cronie
systemctl start docker
systemctl enable docker
systemctl start crond
systemctl enable crond

docker pull igior/weather-app:latest
docker run -d \
  --name weather-app \
  --restart always \
  -p 8080:8080 \
  igior/weather-app:latest

# CloudWatch Agent 

dnf install -y amazon-cloudwatch-agent

# Agent config — tails all three log files and ships to CloudWatch
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/weather-fetcher.log",
            "log_group_name": "/weather-app/fetcher",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/weather-aggregator.log",
            "log_group_name": "/weather-app/aggregator",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/weather-app.log",
            "log_group_name": "/weather-app/app",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%d %H:%M:%S",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# RDS Secret 

# Retry fetching secret up to 20 times with 30s delay
for i in {1..20}; do
  SECRET=$(aws secretsmanager get-secret-value \
    --secret-id rds/postgres/credentials \
    --region us-east-1 \
    --query SecretString \
    --output text 2>/dev/null)

  if [ -n "$SECRET" ]; then
    echo "Secret fetched successfully on attempt $i"
    break
  fi

  echo "Secret not ready yet, retrying in 30s... attempt $i/20"
  sleep 30
done

if [ -z "$SECRET" ]; then
  echo "Failed to fetch secret after 20 attempts, exiting"
  exit 1
fi

DB_HOST=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['host'])")
DB_PORT=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['port'])")
DB_NAME=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['dbname'])")
DB_USER=$(echo $SECRET | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])")
DB_PASS=$(echo $SECRET | python3 -c "import sys,json,base64; print(base64.b64encode(json.load(sys.stdin)['password'].encode()).decode())")

echo "DB_HOST=$DB_HOST DB_PORT=$DB_PORT DB_NAME=$DB_NAME"

# DB Schema 

docker run --rm \
  -e DB_HOST=$DB_HOST \
  -e DB_PORT=$DB_PORT \
  -e DB_NAME=$DB_NAME \
  -e DB_USER=$DB_USER \
  -e DB_PASS=$(echo $DB_PASS | base64 -d) \
  igior/weather-app:latest \
  python3 -c "
import psycopg2, os
conn = psycopg2.connect(
    host=os.getenv('DB_HOST'), port=os.getenv('DB_PORT'),
    dbname=os.getenv('DB_NAME'), user=os.getenv('DB_USER'),
    password=os.getenv('DB_PASS'), sslmode='require'
)
with conn:
    with conn.cursor() as cur:
        cur.execute('''
            CREATE TABLE IF NOT EXISTS weather_readings (
                id SERIAL PRIMARY KEY,
                recorded_at TIMESTAMP NOT NULL,
                temperature NUMERIC(5,2),
                feels_like NUMERIC(5,2),
                humidity INTEGER,
                pressure NUMERIC(7,2),
                wind_speed NUMERIC(5,2),
                wind_direction INTEGER,
                precipitation NUMERIC(5,2),
                visibility NUMERIC(5,2),
                description VARCHAR(100)
            )
        ''')
        cur.execute('''
            CREATE TABLE IF NOT EXISTS weather_hourly_stats (
                hour_start TIMESTAMP PRIMARY KEY,
                avg_temperature NUMERIC(5,2),
                avg_feels_like NUMERIC(5,2),
                avg_humidity NUMERIC(5,2),
                avg_pressure NUMERIC(7,2),
                avg_wind_speed NUMERIC(5,2),
                avg_wind_direction NUMERIC(5,1),
                total_precipitation NUMERIC(5,2),
                avg_visibility NUMERIC(5,2),
                reading_count INTEGER,
                updated_at TIMESTAMP
            )
        ''')
conn.close()
print('Tables created successfully')
"

# Cron Jobs 

mkdir -p /etc/cron.d

cat > /etc/cron.d/weather-fetcher << CRON
*/10 * * * * root docker run --rm -e DB_HOST=$DB_HOST -e DB_PORT=$DB_PORT -e DB_NAME=$DB_NAME -e DB_USER=$DB_USER -e DB_PASS=\$(echo $DB_PASS | base64 -d) igior/weather-app:latest python3 weather-fetcher.py >> /var/log/weather-fetcher.log 2>&1
CRON

cat > /etc/cron.d/weather-aggregator << CRON
55 * * * * root docker run --rm -e DB_HOST=$DB_HOST -e DB_PORT=$DB_PORT -e DB_NAME=$DB_NAME -e DB_USER=$DB_USER -e DB_PASS=\$(echo $DB_PASS | base64 -d) igior/weather-app:latest python3 weather-aggregator.py >> /var/log/weather-aggregator.log 2>&1
CRON

chmod 644 /etc/cron.d/weather-fetcher
chmod 644 /etc/cron.d/weather-aggregator

# Docker app logs -> file (for CloudWatch agent to tail) 

# Redirect weather-app container logs to file so CloudWatch agent can ship them
nohup bash -c 'docker logs -f weather-app >> /var/log/weather-app.log 2>&1' &

echo "Leader setup complete"
