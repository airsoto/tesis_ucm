import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
subprocess.run(["diff", "-qr", "TesisUCM/Resources", str(root)], check=True)
manifest = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
ids = set()
for index in range(manifest["chunks"]):
    path = root / "chunks" / f"chunk_{index:04}.json"
    records = json.loads(path.read_text(encoding="utf-8"))
    for record in records:
        record_id = str(record["_id"])
        if record_id in ids:
            sys.exit(f"Duplicate thesis ID: {record_id}")
        ids.add(record_id)

if len(ids) != manifest["total"]:
    sys.exit(f"Expected {manifest['total']} theses, found {len(ids)}")
shards = list((root / "summary_index").glob("*.json"))
if len(shards) != manifest["summaryIndexShards"]:
    sys.exit(f"Expected {manifest['summaryIndexShards']} index shards, found {len(shards)}")
print(f"Verified {len(ids)} theses and {len(shards)} index shards inside the app.")
