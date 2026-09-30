#!/usr/bin/env python3
"""Google Tasks → JSON for CornerHud.

Outputs a JSON array of tasks: [{title, due, done, notes, list}], where `due` is
"YYYY-MM-DD" (local) or "" if undated. Used by services/Tasks.qml.

First run opens a browser to authorize (scope: tasks.readonly). The token is
cached so later runs are non-interactive. Auth a one-time manual run:

    /usr/bin/python3 ~/.config/quickshell/scripts/gtasks.py --auth

Requires (already pulled in by gcalcli): google-api-python-client,
google-auth-oauthlib. Always invoke with the SYSTEM python (/usr/bin/python3) —
the conda python may lack these libs.

Setup notes:
  * client secret: ~/.config/quickshell/secrets/gcal_client_secret.json
  * token cache:   ~/.config/quickshell/secrets/gtasks_token.json
  * the OAuth client's Google Cloud project must have the *Google Tasks API*
    enabled, and your account added as a test user on the consent screen.
"""
import os, sys, json, datetime

HERE   = os.path.dirname(os.path.abspath(__file__))
SECRET = os.path.expanduser("~/.config/quickshell/secrets/gcal_client_secret.json")
TOKEN  = os.path.expanduser("~/.config/quickshell/secrets/gtasks_token.json")
SCOPES = ["https://www.googleapis.com/auth/tasks.readonly"]


def _creds(interactive=False):
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request
    creds = None
    if os.path.exists(TOKEN):
        creds = Credentials.from_authorized_user_file(TOKEN, SCOPES)
    if creds and creds.valid:
        return creds
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    elif interactive:
        from google_auth_oauthlib.flow import InstalledAppFlow
        flow = InstalledAppFlow.from_client_secrets_file(SECRET, SCOPES)
        creds = flow.run_local_server(port=0)
    else:
        # never pop a browser from the background poller — require an explicit
        # one-time `--auth` run instead.
        raise RuntimeError("not authorized: run `gtasks.py --auth` once")
    with open(TOKEN, "w") as f:
        f.write(creds.to_json())
    os.chmod(TOKEN, 0o600)
    return creds


def _due_local(due):
    # Tasks `due` is an RFC3339 UTC date (time is always 00:00:00Z, date-only).
    if not due:
        return ""
    try:
        return due[:10]  # already a calendar date
    except Exception:
        return ""


def fetch():
    from googleapiclient.discovery import build
    svc = build("tasks", "v1", credentials=_creds(False), cache_discovery=False)
    out = []
    lists = svc.tasklists().list(maxResults=100).execute().get("items", [])
    for tl in lists:
        page = None
        while True:
            resp = svc.tasks().list(tasklist=tl["id"], showCompleted=True,
                                    showHidden=True, maxResults=100,
                                    pageToken=page).execute()
            for t in resp.get("items", []):
                out.append({
                    "title": t.get("title", "").strip(),
                    "due":   _due_local(t.get("due", "")),
                    "done":  t.get("status") == "completed",
                    "notes": t.get("notes", ""),
                    "list":  tl.get("title", ""),
                })
            page = resp.get("nextPageToken")
            if not page:
                break
    return out


if __name__ == "__main__":
    if "--auth" in sys.argv:
        _creds(interactive=True)
        print("authorized; token cached at", TOKEN)
        sys.exit(0)
    try:
        tasks = fetch()
        # undated last; dated ascending
        tasks.sort(key=lambda t: (t["due"] == "", t["due"]))
        print(json.dumps(tasks, ensure_ascii=False))
    except Exception as e:
        # emit valid empty JSON so the UI degrades gracefully; diagnostics to stderr
        sys.stderr.write("gtasks error: %r\n" % e)
        print("[]")
