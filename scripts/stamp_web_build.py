"""Give each web artifact a unique offline cache; run after flutter build web."""
from hashlib import sha256
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def stamp(build: Path) -> str:
    worker = build / "service_worker.js"
    source = (ROOT / "web/service_worker.js").read_text(encoding="utf-8")
    manifest = source.split("const PRECACHE = [", 1)[1].split("];", 1)[0]
    for asset in re.findall(r"'([^']+)'", manifest):
        if not (build / asset).exists():
            raise RuntimeError(f"Required offline asset missing: {asset}")
    digest = sha256(source.encode())
    for path in sorted(build.rglob("*")):
        if path.is_file() and path != worker:
            digest.update(path.relative_to(build).as_posix().encode())
            digest.update(b"\0")
            digest.update(path.read_bytes())
    version = digest.hexdigest()[:20]
    source = re.sub(r"const CACHE = '[^']+';", f"const CACHE = 'athlete-os-shell-{version}';", source, count=1)
    worker.write_text(source, encoding="utf-8")
    return version


if __name__ == "__main__":
    print(f"Offline cache stamped: {stamp(ROOT / 'build/web')}")
