#!/bin/bash

export PGPASSWORD=password

until psql -U root -h postgres -c "SELECT 1" > /dev/null 2>&1; do
  echo "Waiting for postgres..."
  sleep 2
done

psql -U root -h postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'druid'" | grep -q 1 || psql -U root -h postgres -c "CREATE DATABASE druid"

exec ./bin/start-nano-quickstart
