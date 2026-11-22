"""Resolve the newest published Blender LTS Linux x64 release from official sources."""

import json
import os
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


API = "https://projects.blender.org/api/v1/repos/blender/blender/milestones"
RELEASES = "https://download.blender.org/release/"
USER_AGENT = "hermes-devbox-ci/1.0 (+https://github.com/LumenoProject/hermes-devbox)"
RETRYABLE_STATUS = frozenset({403, 429, 500, 502, 503, 504})


def fetch(url, attempts=5):
    # projects.blender.org intermittently answers GitHub Actions runners with
    # 403; retry transient failures with exponential backoff.
    for attempt in range(attempts):
        request = Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urlopen(request, timeout=30) as response:
                return response.read().decode("utf-8")
        except HTTPError as exc:
            if exc.code not in RETRYABLE_STATUS or attempt == attempts - 1:
                raise
            print(f"Retrying {url} after HTTP {exc.code}", file=sys.stderr)
        except (URLError, TimeoutError) as exc:
            if attempt == attempts - 1:
                raise
            print(f"Retrying {url} after {exc}", file=sys.stderr)
        time.sleep(5 * 2**attempt)
    raise AssertionError("unreachable")


class Links(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.hrefs = set()
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.hrefs.update(value for key, value in attrs if key == "href" and value)


def resolve():
    series = set()
    page = 1
    while True:
        milestones = json.loads(fetch(f"{API}?state=open&limit=100&page={page}"))
        if not isinstance(milestones, list):
            raise ValueError("Unexpected milestone API response")
        if not milestones:
            break
        for milestone in milestones:
            match = re.fullmatch(r"(\d+)\.(\d+) LTS", milestone["title"])
            if match:
                series.add(tuple(map(int, match.groups())))
        page += 1

    published = Links(fetch(RELEASES)).hrefs
    for major, minor in sorted(series, reverse=True):
        name = f"{major}.{minor}"
        directory = f"Blender{name}/"
        if directory not in published:
            print(f"Skipping unpublished LTS series {name}", file=sys.stderr)
            continue
        base = RELEASES + directory
        files = Links(fetch(base)).hrefs
        versions = set()
        for filename in files:
            match = re.fullmatch(
                rf"blender-({re.escape(name)}\.\d+)-linux-x64\.tar\.xz", filename
            )
            if match and f"blender-{match[1]}.sha256" in files:
                versions.add(match[1])
        for version in sorted(versions, key=lambda value: tuple(map(int, value.split("."))), reverse=True):
            archive = f"blender-{version}-linux-x64.tar.xz"
            checksums = fetch(base + f"blender-{version}.sha256")
            hashes = [
                fields[0]
                for line in checksums.splitlines()
                if len(fields := line.split()) == 2 and fields[1].lstrip("*") == archive
            ]
            if len(hashes) != 1 or not re.fullmatch(r"[0-9a-fA-F]{64}", hashes[0]):
                raise ValueError(f"Missing or invalid SHA256 for {archive}")
            return version
    raise ValueError("No published Blender LTS Linux x64 release with SHA256 found")


if __name__ == "__main__":
    version = resolve()
    print(version)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(f"version={version}\n")
