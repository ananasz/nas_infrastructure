"""Keep five distinct images per repository and every image built in the last 30 days."""

import argparse
from datetime import datetime, timedelta, timezone
import json
import re
from urllib.parse import quote, urljoin
from urllib.request import Request, urlopen


ACCEPT = ", ".join((
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.docker.distribution.manifest.v2+json",
))


class Registry:
    def __init__(self, url):
        self.url = url.rstrip("/")

    def request(self, path, method="GET"):
        request = Request(urljoin(self.url + "/", path), method=method,
                          headers={"Accept": ACCEPT})
        with urlopen(request, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else None, response.headers

    def listing(self, path, key):
        values = []
        while path:
            body, headers = self.request(path)
            values.extend(body.get(key) or [])
            match = re.search(r'<([^>]+)>;\s*rel="?next"?', headers.get("Link", ""))
            path = match[1] if match else None
        return values

    def tags(self, repo):
        return self.listing(f"/v2/{quote(repo, safe='/')}/tags/list?n=100", "tags")

    def manifest(self, repo, reference, method="GET"):
        body, headers = self.request(
            f"/v2/{quote(repo, safe='/')}/manifests/{quote(reference, safe=':')}", method
        )
        return headers["Docker-Content-Digest"], body

    def blob(self, repo, digest):
        body, _ = self.request(f"/v2/{quote(repo, safe='/')}/blobs/{quote(digest, safe=':')}")
        return body

    def delete(self, repo, digest):
        self.request(f"/v2/{quote(repo, safe='/')}/manifests/{quote(digest, safe=':')}", "DELETE")


def retain_repository(registry, repo, now, dry_run=False):
    manifests = {}
    metadata = {}
    snapshot = {}
    tags_by_digest = {}

    def inspect(digest):
        if digest in metadata:
            return metadata[digest]
        if digest not in manifests:
            _, manifests[digest] = registry.manifest(repo, digest)
        manifest = manifests[digest]
        reachable = {digest}
        created = None
        if "manifests" in manifest:
            dates = []
            for child in manifest["manifests"]:
                date, descendants = inspect(child["digest"])
                reachable.update(descendants)
                if date is not None:
                    dates.append(date)
            if dates:
                created = max(dates)
        elif manifest.get("config"):
            config = registry.blob(repo, manifest["config"]["digest"])
            if config.get("created"):
                created = datetime.fromisoformat(config["created"].replace("Z", "+00:00"))
                if created.tzinfo is None:
                    raise ValueError(f"{repo}@{digest}: image creation time has no timezone")
        metadata[digest] = created, reachable
        return metadata[digest]

    # Finish inventory before deleting anything. Aliases such as latest count once.
    for tag in registry.tags(repo):
        digest, manifest = registry.manifest(repo, tag)
        snapshot[tag] = digest
        tags_by_digest.setdefault(digest, []).append(tag)
        manifests[digest] = manifest
        inspect(digest)

    dated = sorted(
        (digest for digest in tags_by_digest if metadata[digest][0] is not None),
        key=lambda digest: (metadata[digest][0], digest), reverse=True
    )
    keep = set(dated[:5])
    cutoff = now - timedelta(days=30)
    keep.update(digest for digest in tags_by_digest
                if metadata[digest][0] is None or metadata[digest][0] >= cutoff)
    preserved = set()
    expired = set()
    for digest, tags in tags_by_digest.items():
        created, reachable = metadata[digest]
        action = "KEEP" if digest in keep else "DELETE"
        print(f"{action} {repo}@{digest} tags={','.join(sorted(tags))} created={created}", flush=True)
        (preserved if digest in keep else expired).update(reachable)

    # A push during inventory invalidates its decisions; retry on the next daily run.
    current = {tag: registry.manifest(repo, tag, "HEAD")[0] for tag in registry.tags(repo)}
    if current != snapshot:
        print(f"SKIP {repo}: tags changed during inventory", flush=True)
        return

    # Preserve shared platform manifests and every alias of retained images.
    # Delete parents first so an interrupted run cannot leave a tagged index
    # pointing at platform manifests already removed by this run.
    for digest in sorted(expired - preserved, key=lambda value: (-len(metadata[value][1]), value)):
        if not dry_run:
            registry.delete(repo, digest)
        print(f"{'WOULD DELETE' if dry_run else 'DELETED'} {repo}@{digest}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default="http://registry:5000")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    registry = Registry(args.registry)
    now = datetime.now(timezone.utc)
    for repo in registry.listing("/v2/_catalog?n=100", "repositories"):
        retain_repository(registry, repo, now, args.dry_run)


if __name__ == "__main__":
    main()
