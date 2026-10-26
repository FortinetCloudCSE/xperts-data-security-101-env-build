#!/usr/bin/env python3
"""Provision a user's OneDrive using an Azure (Entra ID) app registration.

Steps:
    1. Look up the user principal in Microsoft Graph and check for a SharePoint license.
    2. If the user has no drive yet, ask SharePoint Online to provision the personal site
    (CreatePersonalSiteEnqueueBulk via CSOM on the tenant admin site - the same call
    Request-SPOPersonalSite makes; the REST form of it returns 403 for delegated tokens).
    3. Poll Graph /users/{id}/drive until the drive exists.

App registration setup (application permissions, admin consent granted):
    Microsoft Graph:  User.Read.All, Sites.Read.All
    SharePoint:       Sites.FullControl.All
SharePoint only accepts app-only tokens obtained with a certificate. A client secret works
for the Graph calls, but the provisioning request will be rejected with 401.

SharePoint can refuse CreatePersonalSiteEnqueueBulk for tokens issued to custom app registrations
("Attempted to perform an unauthorized operation"), even delegated ones from a tenant admin. Use --admin-login to
send it as a signed-in SharePoint Administrator through Microsoft's SharePoint Online
Management Shell client (the app Request-SPOPersonalSite uses); no setup on your app is needed.
--admin-client-id overrides the client used for that sign-in.

Configuration (flags or environment variables):
    --tenant-id    AZURE_TENANT_ID
    --client-id    AZURE_CLIENT_ID
    --cert-path    AZURE_CLIENT_CERTIFICATE_PATH      PEM (cert + private key) or PFX
    --cert-password AZURE_CLIENT_CERTIFICATE_PASSWORD  optional
    --client-secret AZURE_CLIENT_SECRET               Graph-only fallback

Usage:
    pip install azure-identity requests
    python provision_onedrive.py user@contoso.com [user2@contoso.com ...] [--timeout 600]
    python provision_onedrive.py --file users.txt    # one UPN per line, # comments allowed
"""
import argparse
import base64
import json
import os
import sys
import time
from urllib.parse import urlparse
from xml.sax.saxutils import escape as xml_escape

import requests
from azure.identity import CertificateCredential, ClientSecretCredential, DeviceCodeCredential

GRAPH = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"
# Microsoft's first-party "SharePoint Online Management Shell" public client.
SPO_SHELL_CLIENT_ID = "9bc3ab49-b65d-410a-85ad-de819febfddc"


def build_credential(args):
    if not args.tenant_id or not args.client_id:
        sys.exit("Tenant ID and client ID are required (--tenant-id/--client-id or AZURE_* env vars).")
    if args.cert_path:
        return CertificateCredential(
            args.tenant_id, args.client_id, args.cert_path, password=args.cert_password
        ), True
    if args.client_secret:
        print(
            "Warning: using a client secret. SharePoint rejects secret-based app-only tokens, "
            "so the provisioning request will likely fail; use --cert-path.",
            file=sys.stderr,
        )
        return ClientSecretCredential(args.tenant_id, args.client_id, args.client_secret), False
    sys.exit("Provide a certificate (--cert-path) or a client secret (--client-secret).")


def graph_get(cred, path, **kw):
    return requests.get(
        f"{GRAPH}{path}",
        headers={"Authorization": f"Bearer {cred.get_token(GRAPH_SCOPE).token}"},
        timeout=60,
        **kw,
    )


def admin_host(cred, override=None):
    """Return the tenant's SharePoint admin host, e.g. contoso-admin.sharepoint.com."""
    if override:
        return f"{override}-admin.sharepoint.com"
    r = graph_get(cred, "/sites/root", params={"$select": "webUrl"})
    r.raise_for_status()
    tenant, domain = urlparse(r.json()["webUrl"]).hostname.split(".", 1)
    return f"{tenant}-admin.{domain}"


def has_sharepoint_license(cred, user_id):
    r = graph_get(cred, f"/users/{user_id}/licenseDetails")
    if not r.ok:
        return None  # unknown; don't block on it
    return any(
        plan["servicePlanName"].startswith("SHAREPOINT")
        and plan["provisioningStatus"] == "Success"
        for lic in r.json().get("value", [])
        for plan in lic.get("servicePlans", [])
    )


def token_claims(access_token):
    """Decode a JWT payload without verifying it (diagnostics only)."""
    payload = access_token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def probe_admin_site(resource, access_token):
    """Show how SharePoint sees this token on the admin site (diagnostics only)."""
    headers = {"Authorization": f"Bearer {access_token}", "Accept": "application/json;odata=nometadata"}
    for path in ("/_api/web/currentuser?$select=LoginName,IsSiteAdmin", "/_api/SPO.Tenant?$select=RootSiteUrl"):
        r = requests.get(f"{resource}{path}", headers=headers, timeout=60)
        print(f"  probe {path.split('?')[0]}: {r.status_code} {r.text[:200]}", file=sys.stderr)


# CSOM request equivalent to Request-SPOPersonalSite. The TypeId is SP.UserProfiles.ProfileLoader,
# taken from SharePoint's SP.UserProfiles.js.
CSOM_ENQUEUE = """<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" \
ApplicationName="provision_onedrive" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009">
<Actions><ObjectPath Id="2" ObjectPathId="1" />
<Method Name="CreatePersonalSiteEnqueueBulk" Id="3" ObjectPathId="1"><Parameters>
<Parameter Type="Array">{emails}</Parameter>
</Parameters></Method></Actions>
<ObjectPaths><StaticMethod Id="1" Name="GetProfileLoader" TypeId="{{9c42543a-91b3-4902-b2fe-14ccdefb6e2b}}" />
</ObjectPaths></Request>"""


ENQUEUE_BATCH = 200  # max users per CreatePersonalSiteEnqueueBulk call


def enqueue_provisioning(cred, host, emails):
    resource = f"https://{host}"
    access_token = cred.get_token(resource + "/.default").token
    objects = "".join(f'<Object Type="String">{xml_escape(e)}</Object>' for e in emails)
    r = requests.post(
        f"{resource}/_vti_bin/client.svc/ProcessQuery",
        headers={"Authorization": f"Bearer {access_token}", "Content-Type": "text/xml"},
        data=CSOM_ENQUEUE.format(emails=objects).encode(),
        timeout=60,
    )
    error = None if r.ok else r.text[:500]
    if r.ok:
        info = r.json()[0].get("ErrorInfo")
        if info:
            error = f"{info.get('ErrorTypeName')}: {info.get('ErrorMessage')}"
    if error:
        claims = token_claims(access_token)
        print(f"Provisioning request failed ({r.status_code}): {error}", file=sys.stderr)
        print(f"  endpoint:    {resource}", file=sys.stderr)
        print(f"  signed in:   {claims.get('upn') or claims.get('unique_name') or '(app-only)'}", file=sys.stderr)
        print(f"  token aud:   {claims.get('aud')}", file=sys.stderr)
        print(f"  token roles: {claims.get('roles')}", file=sys.stderr)
        print(f"  token scp:   {claims.get('scp')}", file=sys.stderr)
        probe_admin_site(resource, access_token)
        if "roles" in claims and "Sites.FullControl.All" not in claims["roles"]:
            print("  -> Add SharePoint (not Microsoft Graph) Sites.FullControl.All as an application "
                    "permission and grant admin consent.", file=sys.stderr)
        elif "roles" in claims:
            print("  -> The app-only token has the right permission, so SharePoint is refusing app-only "
                    "access to this API. Re-run with --admin-login.", file=sys.stderr)
        elif "AllSites.FullControl" in claims.get("scp", ""):
            print("  -> The delegated token is valid. If the SPO.Tenant probe returned 403, the signed-in "
                    "account lacks tenant admin rights (activate a PIM-eligible role first); if it returned "
                    "200, admin rights are fine and SharePoint is refusing this specific API.",
                    file=sys.stderr)
        sys.exit(1)
    print(f"Provisioning queued for {len(emails)} user(s) via {host}.")


def get_drive(cred, user_id):
    r = graph_get(cred, f"/users/{user_id}/drive", params={"$select": "id,webUrl"})
    return r.json() if r.ok else None


def read_user_file(path):
    """One UPN (or object ID) per line; blank lines and # comments are ignored."""
    with open(path, encoding="utf-8-sig") as f:
        return [s for s in (line.split("#", 1)[0].strip() for line in f) if s]


def dedupe(users):
    seen = set()
    return [u for u in users if not (u.lower() in seen or seen.add(u.lower()))]


def main():
    env = os.environ.get
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("users", nargs="*", help="userPrincipalName (or object ID) of each user")
    p.add_argument("-f", "--file", help="File with one userPrincipalName per line (# comments allowed)")
    p.add_argument("--tenant-id", default=env("AZURE_TENANT_ID"))
    p.add_argument("--client-id", default=env("AZURE_CLIENT_ID"))
    p.add_argument("--cert-path", default=env("AZURE_CLIENT_CERTIFICATE_PATH"))
    p.add_argument("--cert-password", default=env("AZURE_CLIENT_CERTIFICATE_PASSWORD"))
    p.add_argument("--client-secret", default=env("AZURE_CLIENT_SECRET"))
    p.add_argument("--tenant-name", help="SharePoint tenant name (contoso in contoso.sharepoint.com); "
                    "detected from Graph if omitted")
    p.add_argument("--timeout", type=int, default=600, help="Seconds to wait for the drive (default 600)")
    p.add_argument("--no-wait", action="store_true", help="Queue provisioning and exit")
    p.add_argument("--admin-login", action="store_true",
                    help="Send the provisioning request as a signed-in SharePoint admin (device code) "
                        "instead of app-only")
    p.add_argument("--admin-client-id", default=SPO_SHELL_CLIENT_ID,
                    help="Client ID for --admin-login (default: SharePoint Online Management Shell)")
    args = p.parse_args()

    users = list(args.users)
    if args.file:
        users += read_user_file(args.file)
    users = dedupe(users)
    if not users:
        p.error("Provide one or more users, or --file.")

    cred, has_cert = build_credential(args)

    results = {}  # input name -> outcome
    pending = {}  # user id -> input name, users that need provisioning
    upns = {}     # user id -> userPrincipalName
    for name in users:
        r = graph_get(cred, f"/users/{name}", params={"$select": "id,displayName,userPrincipalName"})
        if not r.ok:
            results[name] = "user not found" if r.status_code == 404 else f"lookup failed ({r.status_code})"
            print(f"{name}: {results[name]}")
            continue
        user = r.json()
        drive = get_drive(cred, user["id"])
        if drive:
            results[name] = f"already provisioned: {drive['webUrl']}"
        elif has_sharepoint_license(cred, user["id"]) is False:
            results[name] = "no active SharePoint Online license"
        else:
            results[name] = "queued"
            pending[user["id"]] = name
            upns[user["id"]] = user["userPrincipalName"]
        print(f"{name}: {results[name]}")

    if pending:
        provision(args, cred, has_cert, pending, upns, results)

    print(f"\nSummary ({len(users)} user(s)):")
    for name in users:
        print(f"  {name}: {results[name]}")
    ok = ("already provisioned", "provisioned", "queued") if args.no_wait else ("already provisioned", "provisioned")
    if not all(r.startswith(ok) for r in results.values()):
        sys.exit(1)


def provision(args, cred, has_cert, pending, upns, results):
    if args.admin_login:
        sp_cred = DeviceCodeCredential(client_id=args.admin_client_id, tenant_id=args.tenant_id)
    elif has_cert:
        sp_cred = cred
    else:
        sys.exit("OneDrive not provisioned; provisioning requires --cert-path or --admin-login.")

    host = admin_host(cred, args.tenant_name)
    emails = [upns[uid] for uid in pending]
    for i in range(0, len(emails), ENQUEUE_BATCH):
        enqueue_provisioning(sp_cred, host, emails[i:i + ENQUEUE_BATCH])
    if args.no_wait:
        return

    deadline = time.time() + args.timeout
    delay = 10
    while pending and time.time() < deadline:
        time.sleep(delay)
        for uid, name in list(pending.items()):
            drive = get_drive(cred, uid)
            if drive:
                results[name] = f"provisioned: {drive['webUrl']}"
                print(f"{name}: {results[name]}")
                del pending[uid]
        if pending:
            print(f"Waiting for {len(pending)} OneDrive(s)...")
        delay = min(delay * 2, 60)

    for name in pending.values():
        results[name] = "queued, not ready yet (can take up to 24h; re-run to check)"

if __name__ == "__main__":
    main()
