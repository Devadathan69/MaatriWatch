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
        try:
            # Pool.wait() closes the pool permanently if startup times out.
            # Let background connection attempts recover while a request waits
            # only for its own checkout, without changing the pool lifecycle.
            pool.open(wait=False)
            g.db_connection = pool.getconn(timeout=10)
        except DatabaseError:
            abort(503, description="The care service is temporarily unavailable. Your changes were not saved; please try again.")
    return g.db_connection


def database_ready() -> bool:
    """Check an actual connection without exposing connection/error details."""
    pool = current_app.extensions.get("db_pool")
    if not pool:
        return False
    try:
        pool.open(wait=False)
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
        try:
            if not connection.autocommit:
                connection.rollback()
        except DatabaseError:
            # Return a closed connection so the pool replaces it. Never leak
            # a checkout or hide the API response when cleanup loses a socket.
            connection.close()
        finally:
            pool.putconn(connection)
