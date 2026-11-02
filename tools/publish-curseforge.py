#!/usr/bin/env python3
"""Upload a release zip to CurseForge, or list CurseForge's WoW game versions.

Uses CurseForge's upload API: https://support.curseforge.com/support/solutions/articles/9000197321
Standard library only, so the release workflow needs nothing installed.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://wow.curseforge.com/api"


class PublishError(Exception):
    pass


def release_type(tag: str) -> str:
    """vX.Y.Z is a release; a tag such as v2.1.0-beta.1 is published as beta or alpha so players opt in."""
    lowered = tag.lower()
    if "alpha" in lowered:
        return "alpha"
    if "beta" in lowered:
        return "beta"
    return "release"


def parse_game_versions(value: str) -> list[int]:
    ids = [part.strip() for part in value.split(",") if part.strip()]
    if not ids or not all(re.fullmatch(r"\d+", part) for part in ids):
        raise PublishError(
            "CURSEFORGE_GAME_VERSIONS must list CurseForge game version ids, such as 12345 or 12345,12346; "
            "find them with: tools/publish-curseforge.py --list-game-versions"
        )
    return [int(part) for part in ids]


def metadata(tag: str, changelog: str, game_versions: list[int]) -> dict:
    return {
        "displayName": tag,
        "changelog": changelog,
        "changelogType": "markdown",
        "gameVersions": game_versions,
        "releaseType": release_type(tag),
    }


def multipart(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'
        "Content-Type: application/zip\r\n\r\n".encode()
    )
    parts.append(file_path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def request(url: str, token: str, body: bytes | None = None, content_type: str | None = None) -> object:
    req = urllib.request.Request(url, data=body, headers={"X-Api-Token": token})
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read() or b"null")
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        raise PublishError(f"CurseForge answered {error.code} for {url}: {detail}") from error


def list_game_versions(token: str, match: str) -> None:
    versions = request(f"{API}/game/versions", token)
    for version in versions:
        if match.lower() in json.dumps(version).lower():
            print(f"{version.get('id')}\t{version.get('name')}\t{version.get('slug')}\ttype {version.get('gameVersionTypeID')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="the release tag, such as v2.0.0")
    parser.add_argument("--zip", type=Path, help="the release zip")
    parser.add_argument("--changelog", type=Path, help="the CurseForge changelog (markdown)")
    parser.add_argument("--list-game-versions", nargs="?", const="", metavar="TEXT", help="print game versions containing TEXT")
    args = parser.parse_args()

    token = os.environ.get("CURSEFORGE_API_TOKEN", "")
    try:
        if args.list_game_versions is not None:
            if not token:
                raise PublishError("Set CURSEFORGE_API_TOKEN to list game versions.")
            list_game_versions(token, args.list_game_versions)
            return 0
        if not token:
            # Releases still reach GitHub before the CurseForge token is added.
            print("CURSEFORGE_API_TOKEN is not set; skipping the CurseForge upload.")
            return 0
        if not (args.tag and args.zip and args.changelog):
            raise PublishError("--tag, --zip and --changelog are required to upload.")
        project = os.environ.get("CURSEFORGE_PROJECT_ID", "")
        if not re.fullmatch(r"\d+", project):
            raise PublishError("CURSEFORGE_PROJECT_ID must be the project's numeric id.")
        game_versions = parse_game_versions(os.environ.get("CURSEFORGE_GAME_VERSIONS", ""))
        meta = metadata(args.tag, args.changelog.read_text(encoding="utf-8"), game_versions)
        body, content_type = multipart({"metadata": json.dumps(meta)}, "file", args.zip)
        result = request(f"{API}/projects/{project}/upload-file", token, body, content_type)
        print(f"Uploaded {args.zip.name} to CurseForge as a {meta['releaseType']}: file id {result.get('id') if isinstance(result, dict) else result}")
        return 0
    except PublishError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
