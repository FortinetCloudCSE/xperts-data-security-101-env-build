#!/usr/bin/env python3
"""Upload a file to the root of each user's OneDrive using an Azure (Entra ID) app registration.

Uses app-only Microsoft Graph access, so no interactive sign-in is needed. Files up to 4 MB are
sent in one request; larger files use a resumable upload session.

App registration setup (application permissions, admin consent granted):
  Microsoft Graph:  User.Read.All, Files.ReadWrite.All

Configuration (flags or environment variables):
  --tenant-id     AZURE_TENANT_ID
  --client-id     AZURE_CLIENT_ID
  --cert-path     AZURE_CLIENT_CERTIFICATE_PATH      PEM (cert + private key) or PFX
  --cert-password AZURE_CLIENT_CERTIFICATE_PASSWORD  optional
  --client-secret AZURE_CLIENT_SECRET               alternative to a certificate

Usage:
  pip install azure-identity requests
  python upload_onedrive.py report.pdf user@contoso.com [user2@contoso.com ...]
  python upload_onedrive.py report.pdf --file users.txt [--conflict replace]
"""
import argparse
import os
import sys
import time
from urllib.parse import quote

import requests
from azure.identity import CertificateCredential, ClientSecretCredential

from provision_onedrive import GRAPH, GRAPH_SCOPE, dedupe, read_user_file

SIMPLE_UPLOAD_LIMIT = 4 * 1024 * 1024
CHUNK_SIZE = 320 * 1024 * 32  # 10 MiB; upload session chunks must be multiples of 320 KiB


def build_credential(args):
    if not args.tenant_id or not args.client_id:
        sys.exit("Tenant ID and client ID are required (--tenant-id/--client-id or AZURE_* env vars).")
    if args.cert_path:
        return CertificateCredential(args.tenant_id, args.client_id, args.cert_path, password=args.cert_password)
    if args.client_secret:
        return ClientSecretCredential(args.tenant_id, args.client_id, args.client_secret)
    sys.exit("Provide a certificate (--cert-path) or a client secret (--client-secret).")


def graph(cred, method, url, retries=5, **kw):
    """Graph request with retry on throttling (429) and transient errors (503/504)."""
    if not url.startswith("https://"):
        url = f"{GRAPH}{url}"
    headers = {"Authorization": f"Bearer {cred.get_token(GRAPH_SCOPE).token}", **kw.pop("headers", {})}
    for attempt in range(retries):
        r = requests.request(method, url, headers=headers, timeout=120, **kw)
        if r.status_code not in (429, 503, 504) or attempt == retries - 1:
            return r
        time.sleep(int(r.headers.get("Retry-After", 2 ** attempt)))


def error_text(r):
    try:
        return f"{r.status_code} {r.json()['error']['message']}"
    except (ValueError, KeyError):
        return f"{r.status_code} {r.text[:200]}"


def upload(cred, user_id, path, name, conflict):
    """Upload the file to the drive root; returns the new item's webUrl."""
    item = f"/users/{user_id}/drive/root:/{quote(name)}:"
    size = os.path.getsize(path)

    if size <= SIMPLE_UPLOAD_LIMIT:
        with open(path, "rb") as f:
            r = graph(cred, "PUT", f"{item}/content", data=f.read(),
                      params={"@microsoft.graph.conflictBehavior": conflict},
                      headers={"Content-Type": "application/octet-stream"})
        if not r.ok:
            raise RuntimeError(error_text(r))
        return r.json()["webUrl"]

    r = graph(cred, "POST", f"{item}/createUploadSession",
              json={"item": {"@microsoft.graph.conflictBehavior": conflict}})
    if not r.ok:
        raise RuntimeError(error_text(r))
    upload_url = r.json()["uploadUrl"]  # pre-authenticated; must not carry the Graph token
    with open(path, "rb") as f:
        for start in range(0, size, CHUNK_SIZE):
            chunk = f.read(CHUNK_SIZE)
            end = start + len(chunk) - 1
            r = requests.put(upload_url, data=chunk, timeout=300,
                             headers={"Content-Range": f"bytes {start}-{end}/{size}"})
            if not r.ok:
                requests.delete(upload_url, timeout=60)
                raise RuntimeError(error_text(r))
    return r.json()["webUrl"]


def main():
    env = os.environ.get
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source", help="Local file to upload")
    p.add_argument("users", nargs="*", help="userPrincipalName (or object ID) of each user")
    p.add_argument("-f", "--file", help="File with one userPrincipalName per line (# comments allowed)")
    p.add_argument("--name", help="File name in OneDrive (default: the source file's name)")
    p.add_argument("--conflict", choices=("fail", "replace", "rename"), default="fail",
                   help="If the file already exists: fail (default), replace it, or rename the upload")
    p.add_argument("--tenant-id", default=env("AZURE_TENANT_ID"))
    p.add_argument("--client-id", default=env("AZURE_CLIENT_ID"))
    p.add_argument("--cert-path", default=env("AZURE_CLIENT_CERTIFICATE_PATH"))
    p.add_argument("--cert-password", default=env("AZURE_CLIENT_CERTIFICATE_PASSWORD"))
    p.add_argument("--client-secret", default=env("AZURE_CLIENT_SECRET"))
    args = p.parse_args()

    if not os.path.isfile(args.source):
        p.error(f"Source file not found: {args.source}")
    name = args.name or os.path.basename(args.source)
    users = list(args.users)
    if args.file:
        users += read_user_file(args.file)
    users = dedupe(users)
    if not users:
        p.error("Provide one or more users, or --file.")

    cred = build_credential(args)

    results = {}
    for user in users:
        r = graph(cred, "GET", f"/users/{quote(user)}/drive", params={"$select": "id"})
        if r.status_code == 404:
            results[user] = "failed: no OneDrive (user not found or not provisioned; see provision_onedrive.py)"
        elif not r.ok:
            results[user] = f"failed: drive lookup {error_text(r)}"
        else:
            try:
                results[user] = f"uploaded: {upload(cred, quote(user), args.source, name, args.conflict)}"
            except (RuntimeError, requests.RequestException) as e:
                results[user] = f"failed: {e}"
        print(f"{user}: {results[user]}")

    failed = sum(r.startswith("failed") for r in results.values())
    print(f"\n{len(users) - failed} of {len(users)} upload(s) succeeded.")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
