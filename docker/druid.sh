#!/bin/bash

export PGPASSWORD=password
psql -U root -h postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'druid'" | grep -q 1 || psql -U root -h postgres -c "CREATE DATABASE druid"

./bin/start-nano-quickstart
