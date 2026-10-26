#!/usr/bin/env python3
"""Issue a Kladz device-bound activation token using the owner's offline Ed25519 key.

Keep the PEM private key outside the repository and back it up securely.
Requires: python3 -m pip install cryptography
"""
import argparse
import base64
import json
import secrets
import sys
import time
from pathlib import Path
from cryptography.hazmat.primitives.serialization import load_pem_private_key


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def main() -> int:
    parser = argparse.ArgumentParser(description="Issue a Kladz activation key")
    parser.add_argument("--private-key", required=True, help="Path to your private PEM key (never commit it)")
    parser.add_argument("--device-id", required=True, help="Device code shown in the Kladz activation screen")
    parser.add_argument("--days", type=int, default=365, help="License length in days (default: 365; use 36500 for effectively perpetual)")
    args = parser.parse_args()

    if not args.device_id.strip() or len(args.device_id) > 100:
        parser.error("device ID is empty or too long")
    if not 1 <= args.days <= 36500:
        parser.error("--days must be between 1 and 36500")

    try:
        key = load_pem_private_key(Path(args.private_key).read_bytes(), password=None)
    except Exception as exc:
        print(f"Could not read private key: {exc}", file=sys.stderr)
        return 2

    payload = {
        "deviceID": args.device_id.strip().lower(),
        "expiresAt": int(time.time()) + args.days * 86400,
        "licenseID": secrets.token_hex(8),
    }
    payload_encoded = b64url(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    signature = key.sign(payload_encoded.encode("ascii"))
    print(payload_encoded + "." + b64url(signature))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
