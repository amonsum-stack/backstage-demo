# Weather API

REST API for serving weather forecasts, running on EKS.

## Overview

The Weather API is a Node.js service that exposes forecast data via a REST interface.
It stores historical data in RDS PostgreSQL and is deployed on the EKS demo cluster.

## Quick start

```bash
# Get a forecast
curl http://localhost:3000/forecast/London

# Health check
curl http://localhost:3000/health
```

## Dependencies

| Dependency | Type | Notes |
|---|---|---|
| RDS PostgreSQL | Database | Credentials via Secrets Manager |
| S3 | Storage | Weekly pg_dump backups |
