"""Private Daily rooms. Tokens remain transient and never enter audit logs."""

from datetime import datetime, timezone
import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen
from flask import abort, current_app


def room_name(appointment):
    return "mw-" + appointment["id"].replace("-", "")


def daily(method, path, data=None, *, missing_ok=False, conflict_ok=False):
    key = current_app.config.get("DAILY_API_KEY")
    if not key:
        abort(
            503,
            description="Video service is not configured. Your booking remains saved; contact the care team for an alternative.",
        )
    req = Request(
        "https://api.daily.co/v1" + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urlopen(req, timeout=20) as response:
            return json.load(response)
    except HTTPError as error:
        if missing_ok and error.code == 404:
            return None
        if conflict_ok and error.code == 409:
            return None
        abort(
            503,
            description="The video provider is temporarily unavailable. Your appointment is still saved.",
        )
    except (URLError, TimeoutError, ValueError):
        abort(
            503,
            description="The video provider is temporarily unavailable. Please try again.",
        )


def create_join(appointment, actor_id, is_clinician=False, now=None):
    from datetime import timedelta

    now = now or datetime.now(timezone.utc)
    start = datetime.fromisoformat(appointment["start_at"].replace("Z", "+00:00"))
    end = datetime.fromisoformat(appointment["end_at"].replace("Z", "+00:00"))
    if appointment["status"] != "booked":
        abort(409, description="This appointment is no longer booked")
    if now < start - timedelta(minutes=10) or now > end:
        abort(
            409,
            description="Join from ten minutes before the scheduled start until the visit ends",
        )
    name = room_name(appointment)
    expiry = int((end + timedelta(minutes=5)).timestamp())
    room = daily("GET", "/rooms/" + name, missing_ok=True)
    if room is None:
        room = daily(
            "POST",
            "/rooms",
            {
                "name": name,
                "privacy": "private",
                "properties": {
                    "exp": expiry,
                    "eject_at_room_exp": True,
                    "enable_prejoin_ui": True,
                    "enable_chat": False,
                    "enable_screenshare": False,
                },
            },
            conflict_ok=True,
        )
        if room is None:
            room = daily("GET", "/rooms/" + name)
    if (
        not isinstance(room, dict)
        or room.get("name") != name
        or room.get("privacy") != "private"
    ):
        abort(503, description="The video room could not be verified as private")
    url = room.get("url", "")
    parsed = urlsplit(url)
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or not parsed.hostname.endswith(".daily.co")
        or parsed.path.rstrip("/") != "/" + name
        or parsed.query
        or parsed.fragment
    ):
        abort(503, description="The video room address could not be verified")
    token = daily(
        "POST",
        "/meeting-tokens",
        {
            "properties": {
                "room_name": name,
                "user_id": str(actor_id),
                "user_name": "Care team clinician" if is_clinician else "Patient",
                "is_owner": is_clinician,
                "nbf": int((start - timedelta(minutes=10)).timestamp()),
                "exp": expiry,
                "eject_at_token_exp": True,
                "enable_recording_ui": False,
                "start_cloud_recording": False,
                "auto_start_transcription": False,
            }
        },
    )
    if (
        not isinstance(token, dict)
        or not isinstance(token.get("token"), str)
        or not token["token"]
    ):
        abort(503, description="Video access could not be issued")
    return {
        "room_url": url,
        "token": token["token"],
        "expires_at": datetime.fromtimestamp(expiry, timezone.utc).isoformat(),
        "provider": "Daily",
        "notice": "Camera/microphone are used only after you join. Automatic recording and transcription are not enabled.",
    }


def revoke(appointment):
    name = room_name(appointment)
    room = daily("GET", "/rooms/" + name, missing_ok=True)
    if room is not None:
        daily(
            "POST",
            "/rooms/" + name,
            {
                "properties": {
                    "exp": int(datetime.now(timezone.utc).timestamp()),
                    "eject_at_room_exp": True,
                }
            },
        )
