#!/usr/bin/env python3
"""Verify Play app access with an uncommitted edit; never publish changes."""

import json
import os
import re
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2.service_account import Credentials

BASE = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3"
    "/applications/ad.neko.mithka/edits"
)
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def check_access(session):
    response = session.post(BASE, json={}, timeout=30)
    response.raise_for_status()
    edit_id = response.json().get("id", "")
    if not isinstance(edit_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", edit_id):
        raise ValueError("invalid edit identifier")
    url = f"{BASE}/{edit_id}"
    try:
        response = session.get(f"{url}/tracks", timeout=30)
        response.raise_for_status()
        tracks = response.json().get("tracks")
        if not isinstance(tracks, list):
            raise ValueError("invalid track response")
    finally:
        # Deleting an uncommitted edit leaves the published app unchanged.
        response = session.delete(url, timeout=30)
        response.raise_for_status()


def main():
    try:
        info = json.loads(os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"])
        if info.get("type") != "service_account":
            raise ValueError("service-account credential required")
        if info.get("token_uri") != "https://oauth2.googleapis.com/token":
            raise ValueError("unexpected OAuth endpoint")
        credentials = Credentials.from_service_account_info(info, scopes=[SCOPE])
        with AuthorizedSession(credentials) as session:
            check_access(session)
        print("Google Play credential verified for ad.neko.mithka; temporary edit deleted.")
        return 0
    except Exception as error:
        # Provider errors can contain request bodies or bearer tokens. Report
        # only the type and status; never serialize credentials or responses.
        response = getattr(error, "response", None)
        status = getattr(response, "status_code", None)
        print(
            f"Google Play credential check failed ({type(error).__name__}, HTTP {status}).",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
