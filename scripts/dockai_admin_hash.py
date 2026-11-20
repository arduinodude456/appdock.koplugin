#!/usr/bin/env python3
"""Create SQL to provision a DockAI admin password without printing it."""
import base64
import getpass
import hashlib
import secrets

first = getpass.getpass("New DockAI admin password (min. 12 characters): ")
second = getpass.getpass("Repeat password: ")
if first != second:
    raise SystemExit("Passwords do not match.")
if len(first) < 12:
    raise SystemExit("Password must contain at least 12 characters.")
rounds = 310_000
salt = secrets.token_bytes(24)
digest = hashlib.pbkdf2_hmac("sha256", first.encode("utf-8"), salt, rounds, dklen=32)
encoded = "pbkdf2_sha256${}${}${}".format(
    rounds,
    base64.b64encode(salt).decode("ascii"),
    base64.b64encode(digest).decode("ascii"),
)
print("\n-- Paste this SQL into the dchat Supabase SQL Editor; it contains no plaintext password.")
print("insert into public.dockai_admin_config(singleton, password_hash) values (true, '{}' ) ".format(encoded)
      + "on conflict (singleton) do update set password_hash=excluded.password_hash, updated_at=now();")
