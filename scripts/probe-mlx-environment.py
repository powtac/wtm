#!/usr/bin/env python3
"""Offline discovery only: run with an explicit interpreter using -I -S.

Never imports third-party packages, starts a model, installs dependencies, or grants
execution approval. Metadata presence is not a validated Python dependency graph.
"""
import email.parser
import json
import os
from pathlib import Path
import stat
import sys
import sysconfig

REQUIRED = {"mlx", "mlx-lm", "transformers", "tokenizers", "huggingface-hub"}
MAX_METADATA = 65_536


def metadata(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise ValueError("Metadata is not a regular file")
        chunks = bytearray()
        while len(chunks) <= MAX_METADATA:
            chunk = os.read(descriptor, min(8192, MAX_METADATA + 1 - len(chunks)))
            if not chunk:
                break
            chunks.extend(chunk)
        if len(chunks) > MAX_METADATA:
            raise ValueError("Metadata exceeds size limit")
        return email.parser.Parser().parsestr(chunks.decode("utf-8"))
    finally:
        os.close(descriptor)


def report(roots):
    versions = {name: [] for name in sorted(REQUIRED)}
    candidates = {name: [] for name in sorted(REQUIRED)}
    hooks = []
    issues = []
    for root in roots:
        try:
            with os.scandir(root) as entries:
                for count, entry in enumerate(entries):
                    if count >= 10_000:
                        issues.append("Site-packages entry limit reached")
                        break
                    if entry.name.endswith(".pth") or entry.name in (
                        "sitecustomize.py", "usercustomize.py"
                    ):
                        hooks.append(str(root / entry.name))
                    if not entry.name.endswith(".dist-info"):
                        continue
                    normalized = entry.name.lower().replace("_", "-").replace(".", "-")
                    candidate = next((name for name in REQUIRED if normalized.startswith(name + "-")
                                      and normalized[len(name) + 1:len(name) + 2].isdigit()), None)
                    if candidate is None:
                        continue
                    candidates[candidate].append(entry.name)
                    if not entry.is_dir(follow_symlinks=False):
                        issues.append("Symlink or non-directory distribution metadata")
                        continue
                    try:
                        fields = metadata(root / entry.name / "METADATA")
                        name = fields.get("Name", "").lower().replace("_", "-").replace(".", "-")
                        if name in versions:
                            versions[name].append(fields.get("Version", "unknown"))
                    except (OSError, ValueError) as error:
                        issues.append(entry.name + ": " + type(error).__name__ + ": metadata not verified")
        except OSError:
            issues.append("Unreadable site-packages root")
    return {
        "schemaVersion": 1,
        "runtimeEnabled": False,
        "scope": "metadata discovery only; no dependency graph or launch approval",
        "packages": versions,
        "candidates": candidates,
        "notObserved": sorted(name for name, values in candidates.items() if not values),
        "startupHooks": sorted(hooks),
        "issues": issues,
    }


def main():
    if not (sys.flags.isolated and sys.flags.no_site):
        sys.exit("Run with an explicit Python interpreter and -I -S.")
    roots = sorted({Path(sysconfig.get_path(key)) for key in ("purelib", "platlib")})
    result = report(roots)
    result["pythonVersion"] = sys.version.split()[0]
    result["interpreter"] = str(Path(sys.executable).resolve())
    result["sitePackages"] = [str(root) for root in roots]
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
