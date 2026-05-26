# Runbook

## Checking pod status

```bash
kubectl get pods -n weather
kubectl logs -n weather deployment/weather-api
```

## Restarting the service

```bash
kubectl rollout restart deployment/weather-api -n weather
```

## Checking database connectivity

```bash
kubectl exec -n weather deployment/weather-api -- \
  node -e "require('./dist/db').ping().then(console.log)"
```

## CloudWatch alarms

| Alarm | Threshold | Action |
|---|---|---|
| rds-cpu-high | >90% for 5 min | Check slow queries |
| rds-storage-low | <4GB free | Expand or clean up |
| rds-connections-high | >48 connections | Check for connection leaks |
| rds-instance-down | No data | Check RDS console |

## Restoring from backup

Backups are stored in S3 under `backups/` as `.sql.gz` files.

```bash
# List backups
aws s3 ls s3://<backup-bucket>/backups/

# Restore
aws s3 cp s3://<backup-bucket>/backups/<file>.sql.gz .
gunzip <file>.sql.gz
psql -h <rds-host> -U postgres postgres_db < <file>.sql
```
