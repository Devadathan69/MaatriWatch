"""Firebase identity verification and database-backed RBAC."""

from __future__ import annotations

from functools import wraps

from firebase_admin import auth as firebase_auth
from flask import Blueprint, abort, current_app, g, jsonify, request

from .db import get_db
from .firebase import sync_clinician_entitlements

auth_bp = Blueprint("auth", __name__)


def verified_firebase_identity():
    """Authenticate an identity before it has been linked to an app role."""
    if not current_app.config.get("FIREBASE_AUTH_READY"):
        abort(503, description="Firebase authentication is unavailable")
    scheme, _, token = request.headers.get("Authorization", "").partition(" ")
    if scheme.lower() != "bearer" or not token:
        abort(401, description="A Firebase bearer token is required")
    try:
        claims = firebase_auth.verify_id_token(token, check_revoked=True)
    except Exception:
        abort(401, description="The Firebase token is invalid or expired")
    if claims.get("email_verified") is not True or not claims.get("email"):
        abort(403, description="Verify your email before linking a guardian account")
    return claims


def require_verified_identity(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        g.firebase_claims = verified_firebase_identity()
        return view(*args, **kwargs)
    return wrapped
_DEMO_ROLE_UIDS = {
    "clinician": "demo-doctor",
    "doctor": "demo-doctor",
    "patient": "demo-patient-1",
    "hospital_admin": "demo-admin",
    "admin": "demo-admin",
}


def require_firebase_user(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        # The hackathon role picker identifies itself with this header. It is
        # ignored unless the server was explicitly started with DEMO_MODE=true.
        demo_role = request.headers.get("X-Demo-Role", "").strip().lower()
        if current_app.config.get("DEMO_MODE") and demo_role in _DEMO_ROLE_UIDS:
            if current_app.config.get("DEMO_IN_MEMORY"):
                g.firebase_claims = {"uid": _DEMO_ROLE_UIDS[demo_role], "demo": True}
                g.actor = {
                    "id": f"memory-{demo_role}",
                    "firebase_uid": _DEMO_ROLE_UIDS[demo_role],
                    "display_name": "Demo clinician" if demo_role in {"doctor", "clinician"} else "Demo user",
                    "is_active": True,
                }
                g.demo_role = demo_role
                return view(*args, **kwargs)
            actor = lookup_app_user(_DEMO_ROLE_UIDS[demo_role])
            if not actor or not actor["is_active"]:
                abort(503, description="Demo users are not seeded yet")
            g.firebase_claims = {"uid": actor["firebase_uid"], "demo": True}
            g.actor = actor
            g.demo_role = demo_role
            return view(*args, **kwargs)
        if not (current_app.config.get("FIREBASE_AUTH_READY") or current_app.config.get("FIREBASE_READY")):
            abort(503, description="Firebase authentication is unavailable")
        header = request.headers.get("Authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer" or not token:
            abort(401, description="A Firebase bearer token is required")
        try:
            decoded = firebase_auth.verify_id_token(token, check_revoked=True)
        except Exception:
            abort(401, description="The Firebase token is invalid or expired")
        g.firebase_claims = decoded
        g.actor = lookup_app_user(decoded["uid"])
        if not g.actor or not g.actor["is_active"]:
            abort(403, description="This account is inactive or has not been provisioned")
        return view(*args, **kwargs)

    return wrapped


def lookup_app_user(firebase_uid: str):
    with get_db().cursor() as cursor:
        cursor.execute(
            "SELECT id, firebase_uid, email, phone_e164, display_name, is_active FROM app_users WHERE firebase_uid = %s",
            (firebase_uid,),
        )
        return cursor.fetchone()


def memberships_for(user_id: str):
    with get_db().cursor() as cursor:
        cursor.execute(
            """SELECT hm.hospital_id, hm.role, h.name AS hospital_name
                 FROM hospital_memberships hm JOIN hospitals h ON h.id = hm.hospital_id
                 WHERE hm.user_id = %s AND hm.is_active = true""",
            (user_id,),
        )
        return cursor.fetchall()


def memberships_for_realtime(user_id: str):
    """All memberships, including inactive records, for RTDB grant refresh."""
    with get_db().cursor() as cursor:
        cursor.execute(
            """SELECT hospital_id, role, is_active
                 FROM hospital_memberships
                 WHERE user_id = %s""",
            (user_id,),
        )
        return cursor.fetchall()


def require_hospital_role(*roles):
    """Require a current active role at the hospital selected by a trusted route value."""
    def decorator(view):
        @wraps(view)
        @require_firebase_user
        def wrapped(*args, **kwargs):
            hospital_id = kwargs.get("hospital_id")
            if not hospital_id:
                abort(500, description="Protected route must provide hospital_id")
            if current_app.config.get("DEMO_IN_MEMORY"):
                from .demo_store import DEMO_HOSPITAL_ID

                if getattr(g, "demo_role", None) in {"clinician", "doctor"} and str(hospital_id) == DEMO_HOSPITAL_ID:
                    return view(*args, **kwargs)
                abort(403, description="This demo role cannot access that hospital")
            memberships = memberships_for(g.actor["id"])
            if not any(str(row["hospital_id"]) == str(hospital_id) and row["role"] in roles for row in memberships):
                abort(403, description="You do not have access to this hospital")
            return view(*args, **kwargs)
        return wrapped
    return decorator


@auth_bp.get("/me")
@require_firebase_user
def current_user():
    if current_app.config.get("DEMO_IN_MEMORY") and getattr(g, "demo_role", None):
        from .demo_store import DEMO_HOSPITAL_ID, demo_store

        role = "clinician" if g.demo_role in {"clinician", "doctor"} else "hospital_admin" if g.demo_role in {"admin", "hospital_admin"} else "patient"
        return jsonify(
            {
                "user": {
                    "id": str(g.actor["id"]),
                    "firebase_uid": g.actor["firebase_uid"],
                    "display_name": g.actor["display_name"],
                },
                "hospital_memberships": [
                    {"hospital_id": DEMO_HOSPITAL_ID, "hospital_name": demo_store.hospital["name"], "role": role}
                ],
            }
        )
    memberships = memberships_for(g.actor["id"])
    # The browser connects directly to RTDB for live overlays. Refresh its
    # narrow read grants on each dashboard session; Postgres remains the
    # source of authority and REST continues to work if RTDB is unavailable.
    sync_clinician_entitlements(g.actor["firebase_uid"], memberships_for_realtime(g.actor["id"]))
    return jsonify(
        {
            "user": {
                "id": str(g.actor["id"]),
                "firebase_uid": g.actor["firebase_uid"],
                "display_name": g.actor["display_name"],
            },
            "hospital_memberships": [
                {"hospital_id": str(row["hospital_id"]), "hospital_name": row["hospital_name"], "role": row["role"]}
                for row in memberships
            ],
        }
    )
