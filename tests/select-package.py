"""Select a server from a standard APT Packages index using Debian ordering."""

import argparse
import json
import re
import sys
import subprocess
from pathlib import Path

from debian.deb822 import Packages
from debian.debian_support import Version

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["amd64", "arm64"])
parser.add_argument("--slot", default="")
parser.add_argument("--exact-version", default="")
parser.add_argument("--cli-version", default="")
parser.add_argument("--all", action="store_true", help="Plan stable image reconciliation")
parser.add_argument("--amd64", type=Path)
parser.add_argument("--arm64", type=Path)
parser.add_argument("--labels", type=Path, help="Fixture labels keyed by slot; otherwise inspect GHCR")
args = parser.parse_args()


def inventory(path, arch):
    versions = {}
    with path.open() as source:
        for entry in Packages.iter_paragraphs(source):
            name = entry["Package"]
            if entry["Architecture"] != arch or not re.fullmatch(r"gel-server-[0-9]+|gel-cli", name):
                continue
            version = entry["Version"]
            if not re.fullmatch(r"1:[0-9][0-9A-Za-z.+~]*-[0-9]+", version):
                parser.error("expected a full native version with epoch 1 and numeric revision")
            if name not in versions or Version(version) > Version(versions[name]):
                versions[name] = version
    return versions


if args.all:
    if not args.amd64 or not args.arm64:
        parser.error("--all requires --amd64 and --arm64")
    packages = inventory(args.amd64, "amd64")
    if packages != inventory(args.arm64, "arm64"):
        parser.error("amd64 and arm64 package versions disagree")
    slots = sorted((name.removeprefix("gel-server-") for name in packages if name.startswith("gel-server-")), key=int)
    if args.slot and args.slot not in slots:
        parser.error("forced slot is absent from the Packages indexes")
    if slots and "gel-cli" not in packages:
        parser.error("server packages require gel-cli on both architectures")
    labels = json.loads(args.labels.read_text()) if args.labels else None
    planned = []
    for slot in slots:
        server = packages[f"gel-server-{slot}"]
        cli = packages["gel-cli"]
        if labels is not None:
            current = labels.get(slot, {})
        else:
            result = subprocess.run([
                "docker", "buildx", "imagetools", "inspect",
                f"ghcr.io/gelstable/gel:{slot}", "--format", "{{json .Image}}",
            ], capture_output=True, text=True)
            if result.returncode:
                if not any(marker in result.stderr.lower() for marker in ("manifest unknown", "not found")):
                    sys.exit(result.stderr)
                current = {}
            else:
                image = json.loads(result.stdout)
                # Multi-platform .Image is keyed by platform; require every image to match.
                images = [image] if "config" in image else list(image.values())
                wanted = {"com.gelstable.server-version": server, "com.gelstable.cli-version": cli}
                current = wanted if images and all(all(item.get("config", {}).get("Labels", {}).get(k) == v for k, v in wanted.items()) for item in images) else {}
        if slot == args.slot or current.get("com.gelstable.server-version") != server or current.get("com.gelstable.cli-version") != cli:
            tag = server.split(":", 1)[1].rsplit("-", 1)[0].replace("~", "-")
            planned.append({"slot": slot, "version": server, "cli_version": cli,
                            "tags": [slot, tag] + (["latest"] if slot == slots[-1] else [])})
    print(json.dumps({"include": planned}))
    sys.exit(0)

if not args.arch:
    parser.error("--arch is required for single-package selection")
servers = []
cli_versions = []
for entry in Packages.iter_paragraphs(sys.stdin):
    if entry["Package"] == "gel-cli" and entry["Architecture"] == args.arch:
        cli_versions.append(entry["Version"])
    match = re.fullmatch(r"gel-server-([0-9]+)", entry["Package"])
    if match and entry["Architecture"] == args.arch:
        servers.append((match[1], entry["Version"]))
if not servers:
    parser.error("no native server packages found for this architecture")
if args.cli_version and args.cli_version not in cli_versions:
    parser.error("requested CLI version is absent from the Packages index")
if not cli_versions:
    parser.error("no native CLI packages found for this architecture")
latest_slot = max((slot for slot, _ in servers), key=int)
candidates = [
    (slot, version)
    for slot, version in servers
    if (not args.slot or slot == args.slot)
    and (not args.exact_version or version == args.exact_version)
]
if not candidates:
    parser.error("requested native server version is absent from the Packages index")
slot, version = max(candidates, key=lambda item: (int(item[0]), Version(item[1])))
# Native packages have an epoch and a package revision; image tags name the product.
if not re.fullmatch(r"1:[0-9][0-9A-Za-z.+~]*-[0-9]+", version):
    parser.error("expected a full native version with epoch 1 and numeric revision")
product_version = version.split(":", 1)[1].rsplit("-", 1)[0]
print(
    json.dumps(
        {
            "cli_version": args.cli_version or max(cli_versions, key=Version),
            "slot": slot,
            "version": version,
            "product_version": product_version,
            "tag": product_version.replace("~", "-"),
            "latest_slot": latest_slot,
        }
    )
)
