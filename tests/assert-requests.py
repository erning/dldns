#!/usr/bin/env python3

import json
import os
from pathlib import Path
import sys


expected = json.load(sys.stdin)
base_url = os.environ["DLDNS_LINODE_API_URL"]
actual = []
for line in Path(sys.argv[1]).read_text().splitlines():
    method, url, body = line.split("\t", 2)
    if not url.startswith(base_url + "/"):
        raise SystemExit(f"unexpected API URL: {url}")
    actual.append([method, url[len(base_url):], json.loads(body) if body else None])

if actual != expected:
    print("not ok - API requests differ")
    print("expected:", json.dumps(expected, indent=2))
    print("actual:", json.dumps(actual, indent=2))
    raise SystemExit(1)
