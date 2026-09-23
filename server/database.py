"""PostgreSQL connections and tracked, transactional schema bootstrapping."""

import hashlib
import os
from pathlib import Path
import re

import psycopg
from psycopg.rows import dict_row


def connect() -> psycopg.Connection:
    """Each context commits on success and rolls back on an exception."""
    options = {"row_factory": dict_row, "connect_timeout": 5,
               "options": "-c statement_timeout=15000 -c lock_timeout=5000"}
    if os.environ.get("DATABASE_URL"):
        return psycopg.connect(os.environ["DATABASE_URL"], **options)
    return psycopg.connect(host=os.environ["DB_HOST"], dbname=os.environ["DB_NAME"],
                           user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"],
                           **options)


def migrate() -> None:
    """Apply each migration or bootstrap seed once; reject edited applied SQL."""
    root = Path(__file__).resolve().parents[1] / "db"
    scripts = sorted([*root.glob("migrations/*.sql"), *root.glob("seed/*.sql")], key=lambda p: p.name)
    with connect() as conn:
        conn.execute("SELECT pg_advisory_xact_lock(4952026)")
        conn.execute("""CREATE TABLE IF NOT EXISTS public.aa_schema_migrations (
            name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())""")
        for script in scripts:
            sql = script.read_text()
            checksum = hashlib.sha256(sql.encode()).hexdigest()
            applied = conn.execute("SELECT checksum FROM public.aa_schema_migrations WHERE name=%s",
                                   (script.name,)).fetchone()
            if applied:
                if applied["checksum"] != checksum:
                    raise RuntimeError(f"Applied migration changed: {script.name}")
                continue
            # The original SQL supports psql, but this runner owns the transaction.
            sql = re.sub(r"(?m)^\s*(BEGIN|COMMIT);\s*$", "", sql)
            conn.execute(sql)
            conn.execute("INSERT INTO public.aa_schema_migrations(name,checksum) VALUES (%s,%s)",
                         (script.name, checksum))
            print(f"Applied {script.name}", flush=True)


if __name__ == "__main__":
    migrate()
