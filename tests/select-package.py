"""Select a server from a standard APT Packages index using Debian ordering."""

import argparse
import json
import re
import sys

from debian.deb822 import Packages
from debian.debian_support import Version

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", required=True, choices=["amd64", "arm64"])
parser.add_argument("--slot", default="")
parser.add_argument("--exact-version", default="")
args = parser.parse_args()
servers = []
for entry in Packages.iter_paragraphs(sys.stdin):
    match = re.fullmatch(r"gel-server-([0-9]+)", entry["Package"])
    if match and entry["Architecture"] == args.arch:
        servers.append((match[1], entry["Version"]))
if not servers:
    parser.error("no native server packages found for this architecture")
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
            "slot": slot,
            "version": version,
            "product_version": product_version,
            "tag": product_version.replace("~", "-"),
            "latest_slot": latest_slot,
        }
    )
)
