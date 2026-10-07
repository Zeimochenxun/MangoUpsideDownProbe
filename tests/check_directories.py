"""Inspect raw tar directory records; regular extractors silently hide this bug."""
import io
import pathlib
import sys
import tarfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "tools"))
from deb import read_ar


def check_directory_members(package):
    counts = {}
    for section in ("control", "data"):
        entries = read_ar(package)
        raw = next(v for k, v in entries.items() if k.startswith(section + ".tar"))
        directories, names = set(), set()
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as archive:
            for item in archive:
                path = pathlib.PurePosixPath(item.name)
                assert not path.is_absolute() and ".." not in path.parts
                assert path not in names, f"Duplicate archive path: {path}"
                names.add(path)
                assert item.uid == item.gid == 0
                for parent in path.parents:
                    assert parent in directories, f"Missing preceding directory record: {parent} (for {path})"
                if item.isdir():
                    assert item.mode == 0o755, f"Bad directory mode: {path}"
                    directories.add(path)
                else:
                    assert item.isfile() or item.issym()
        assert pathlib.PurePosixPath(".") in directories
        counts[section] = len(directories)
    return counts


if __name__ == "__main__":
    print(check_directory_members(sys.argv[1]))
