# Load .env into every recipe so dbt and the loader see the warehouse credentials.
SHELL := /bin/bash
ENV := set -a && source .env && set +a
DBT := $(ENV) && cd dbt && DBT_PROFILES_DIR=. ../.venv/bin/dbt
DATA_URL := https://github.com/sql-bi/Contoso-Data-Generator-V2-Data/releases/download/ready-to-use-data/csv-1m.7z

.PHONY: setup up data load build test docs

setup:            ## Create the virtualenv and install dbt packages
	python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	$(DBT) deps

up:               ## Start the Postgres warehouse
	docker compose up -d warehouse

data:             ## Download and unpack the Contoso 1M-order CSV extract (49 MB)
	mkdir -p data/download data/raw
	curl -sSL -o data/download/csv-1m.7z $(DATA_URL)
	.venv/bin/python -I scripts/unpack.py data/download/csv-1m.7z data/raw

load:             ## Load the CSVs into raw.* (skips files that haven't changed)
	.venv/bin/python -I ingest/load_raw.py data/raw

build:            ## Seed, run and test every model
	$(DBT) build

test:
	$(DBT) test

docs:             ## Generate and serve dbt docs on http://localhost:8081
	$(DBT) docs generate && $(DBT) docs serve --port 8081
