"""
Uploads the four audio banks to Roblox and writes their ids into
src/shared/Config/AudioAssets.luau.

  Upload with Open Cloud (needs an API key with the Assets API's read and
  write permissions, created on the Creator Dashboard):

    ROBLOX_API_KEY=... python3 scripts/audio/upload.py --user 123456
    ROBLOX_API_KEY=... python3 scripts/audio/upload.py --group 7890

  Use the user or group that owns the experience; Roblox only lets an
  experience play audio its owner is allowed to use.

  Or upload assets/audio/DeadAir_*.ogg by hand on the Creator Dashboard and
  just write the ids:

    python3 scripts/audio/upload.py --ids Sfx=111 Ambience=222 Music1=333 Music2=444

Only the Python standard library is used.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")
ASSETS_LUAU = os.path.join(ROOT, "src", "shared", "Config", "AudioAssets.luau")
API = "https://apis.roblox.com/assets/v1"


def banks():
    with open(os.path.join(AUDIO, "banks.json")) as f:
        return json.load(f)["banks"]


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as err:
        detail = err.read().decode("utf-8", "replace")
        raise SystemExit("%s %s failed: HTTP %d\n%s" % (method, url, err.code, detail))


def upload(path, name, key, creator):
    boundary = uuid.uuid4().hex
    meta = {
        "assetType": "Audio",
        "displayName": name,
        "description": "DEAD AIR: CHANNEL ZERO original audio bank (%s)." % name,
        "creationContext": {"creator": creator},
    }
    with open(path, "rb") as f:
        data = f.read()
    body = b"".join(
        [
            ("--%s\r\n" % boundary).encode(),
            b'Content-Disposition: form-data; name="request"\r\n',
            b"Content-Type: application/json\r\n\r\n",
            json.dumps(meta).encode(),
            ("\r\n--%s\r\n" % boundary).encode(),
            ('Content-Disposition: form-data; name="fileContent"; filename="%s"\r\n' % os.path.basename(path)).encode(),
            b"Content-Type: audio/ogg\r\n\r\n",
            data,
            ("\r\n--%s--\r\n" % boundary).encode(),
        ]
    )
    op = request("POST", API + "/assets", key, body, "multipart/form-data; boundary=" + boundary)
    # Uploads are processed asynchronously: poll the operation until done.
    path_id = op.get("path", "")
    for _ in range(60):
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", API + "/" + path_id, key)
    if not op.get("done"):
        raise SystemExit("Upload of %s did not finish; check the Creator Dashboard." % name)
    response = op.get("response", {})
    asset_id = response.get("assetId")
    if not asset_id:
        raise SystemExit("Upload of %s returned no asset id:\n%s" % (name, json.dumps(op, indent=1)))
    return str(asset_id)


def write_ids(ids):
    with open(ASSETS_LUAU) as f:
        text = f.read()
    for bank, asset_id in ids.items():
        value = asset_id if asset_id.startswith("rbxassetid://") else "rbxassetid://" + asset_id
        pattern = r'(\n\t%s = )"[^"]*",' % re.escape(bank)
        if not re.search(pattern, text):
            raise SystemExit("No entry for bank %s in AudioAssets.luau" % bank)
        text = re.sub(pattern, lambda m: '%s"%s",' % (m.group(1), value), text)
    with open(ASSETS_LUAU, "w") as f:
        f.write(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    who = parser.add_mutually_exclusive_group()
    who.add_argument("--user", help="upload as this Roblox user id")
    who.add_argument("--group", help="upload as this Roblox group id")
    parser.add_argument("--ids", nargs="*", help="skip uploading; write Bank=assetId pairs")
    args = parser.parse_args()

    known = banks()
    if args.ids:
        ids = {}
        for pair in args.ids:
            bank, _, asset_id = pair.partition("=")
            if bank not in known or not asset_id.strip():
                raise SystemExit("Expected Bank=assetId with Bank one of: " + ", ".join(sorted(known)))
            ids[bank] = asset_id.strip()
        write_ids(ids)
        print("Wrote %d id(s) to %s" % (len(ids), os.path.relpath(ASSETS_LUAU, ROOT)))
        return

    key = os.environ.get("ROBLOX_API_KEY")
    if not key or not (args.user or args.group):
        parser.print_help()
        sys.exit(2)
    creator = {"userId": str(args.user)} if args.user else {"groupId": str(args.group)}
    ids = {}
    for bank, info in sorted(known.items()):
        path = os.path.join(AUDIO, info["file"])
        print("Uploading %s (%.0f s)..." % (info["file"], info["duration"]))
        ids[bank] = upload(path, "DeadAir " + bank, key, creator)
        print("  -> rbxassetid://%s" % ids[bank])
    write_ids(ids)
    print("Wrote ids to %s. Rebuild the place (scripts/build.sh) to use them." % os.path.relpath(ASSETS_LUAU, ROOT))


if __name__ == "__main__":
    main()
