"""Postgres pool and request helpers."""

from __future__ import annotations

from flask import abort, current_app, g
from psycopg import Error as DatabaseError
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


def init_db(app):
    database_url = app.config.get("DATABASE_URL")
    app.extensions["db_pool"] = (
        # API and workers each own a pool. Reserve one idle session per process
        # so small hosted Session poolers still have room for all services.
        ConnectionPool(
            conninfo=database_url, kwargs={"row_factory": dict_row},
            min_size=1, max_size=4, open=False,
        )
        if database_url
        else None
    )


def get_db():
    pool = current_app.extensions.get("db_pool")
    if not pool:
        abort(503, description="Database is not configured")
    if "db_connection" not in g:
        pool.open(wait=True)
        g.db_connection = pool.getconn()
    return g.db_connection


def database_ready() -> bool:
    """Check an actual connection without exposing connection/error details."""
    pool = current_app.extensions.get("db_pool")
    if not pool:
        return False
    try:
        pool.open(wait=True, timeout=3)
        with pool.connection(timeout=3) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
                return cursor.fetchone() is not None
    except DatabaseError:
        return False


def close_db(_exception=None):
    connection = g.pop("db_connection", None)
    pool = current_app.extensions.get("db_pool")
    if connection and pool:
        # SELECT-only requests still start a transaction; never return one to the pool open.
        if not connection.autocommit:
            connection.rollback()
        pool.putconn(connection)
