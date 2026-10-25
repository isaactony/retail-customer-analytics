"""Load the Contoso CSV extract into raw.* tables, exactly as delivered.

Every column lands as text (typing happens in dbt), one table per file. A file is reloaded
only when its SHA-256 changes, and every load is recorded in raw._loads.

    python -I ingest/load_raw.py data/raw
"""

import hashlib
import os
import pathlib
import re
import sys

import psycopg
from dotenv import load_dotenv

FILES = ["currencyexchange", "customer", "date", "orderrows", "orders", "product", "sales", "store"]

MANIFEST = """
CREATE TABLE IF NOT EXISTS raw._loads (
    load_id     bigserial PRIMARY KEY,
    file_name   text        NOT NULL,
    sha256      text        NOT NULL,
    bytes       bigint      NOT NULL,
    row_count   bigint      NOT NULL,
    loaded_at   timestamptz NOT NULL DEFAULT now()
);
"""


def snake(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(raw_dir):
    load_dotenv(pathlib.Path(__file__).resolve().parent.parent / ".env")
    conn = psycopg.connect(
        host=os.environ["WAREHOUSE_HOST"], port=os.environ["WAREHOUSE_PORT"],
        dbname=os.environ["WAREHOUSE_DB"], user=os.environ["WAREHOUSE_USER"],
        password=os.environ["WAREHOUSE_PASSWORD"], autocommit=True,
    )
    conn.execute(MANIFEST)
    for name in FILES:
        path = pathlib.Path(raw_dir) / f"{name}.csv"
        digest = sha256(path)
        last = conn.execute(
            "SELECT sha256 FROM raw._loads WHERE file_name = %s ORDER BY load_id DESC LIMIT 1", (path.name,)
        ).fetchone()
        if last and last[0] == digest:
            print(f"{path.name}: unchanged, skipped")
            continue

        with open(path, encoding="utf-8-sig") as f:
            header = f.readline().strip().split(",")
        columns = [snake(c) for c in header]
        table = f"raw.{name}"
        with conn.transaction():
            conn.execute(f"DROP TABLE IF EXISTS {table}")
            conn.execute(f"CREATE TABLE {table} ({', '.join(f'{c} text' for c in columns)})")
            with conn.cursor() as cur, open(path, "rb") as f:
                with cur.copy(f"COPY {table} FROM STDIN WITH (FORMAT csv, HEADER true)") as copy:
                    while chunk := f.read(1 << 20):
                        copy.write(chunk)
            rows = conn.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
            conn.execute(
                "INSERT INTO raw._loads (file_name, sha256, bytes, row_count) VALUES (%s, %s, %s, %s)",
                (path.name, digest, path.stat().st_size, rows),
            )
        print(f"{path.name}: loaded {rows:,} rows into {table}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "data/raw")
