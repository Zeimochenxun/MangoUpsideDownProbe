"""Small deterministic Debian archive reader/writer; no external dpkg needed."""
import gzip
import hashlib
import io
import pathlib
import tarfile


def read_ar(path):
    blob = pathlib.Path(path).read_bytes()
    if not blob.startswith(b"!<arch>\n"):
        raise ValueError("Not an ar archive")
    result, pos = {}, 8
    while pos < len(blob):
        header = blob[pos:pos + 60]
        if len(header) != 60 or header[-2:] != b"`\n":
            raise ValueError("Invalid ar member")
        name = header[:16].decode().strip().rstrip("/")
        size = int(header[48:58])
        result[name] = blob[pos + 60:pos + 60 + size]
        if len(result[name]) != size:
            raise ValueError("Truncated ar member")
        pos += 60 + size + (size % 2)
    return result


def read_deb(path):
    members = read_ar(path)
    result = {}
    for kind in ("control", "data"):
        raw = next(v for k, v in members.items() if k.startswith(kind + ".tar"))
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as archive:
            files = {}
            for member in archive:
                name = member.name.removeprefix("./")
                if member.isfile():
                    files[name] = (archive.extractfile(member).read(), member.mode)
                elif member.issym():
                    files[name] = (member.linkname, member.mode)
                elif not member.isdir():
                    raise ValueError(f"Unsupported tar member: {name}")
            result[kind] = files
    return result


def make_tar(files):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, (data, mode) in sorted(files.items()):
            if name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts:
                raise ValueError(name)
            item = tarfile.TarInfo("./" + name)
            item.uid = item.gid = 0
            item.uname = item.gname = "root"
            item.mtime = 0
            item.mode = mode
            if isinstance(data, str):
                item.type, item.linkname = tarfile.SYMTYPE, data
                archive.addfile(item)
            else:
                item.size = len(data)
                archive.addfile(item, io.BytesIO(data))
    return gzip.compress(stream.getvalue(), mtime=0)


def write_deb(path, control, data):
    result = bytearray(b"!<arch>\n")
    for name, blob in (("debian-binary", b"2.0\n"),
                       ("control.tar.gz", make_tar(control)),
                       ("data.tar.gz", make_tar(data))):
        header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(blob):<10}`\n"
        if len(header) != 60:
            raise ValueError("Invalid ar header length")
        result.extend(header.encode("ascii"))
        result.extend(blob)
        if len(blob) % 2:
            result.extend(b"\n")
    pathlib.Path(path).write_bytes(result)


def sha256(blob):
    return hashlib.sha256(blob).hexdigest()


if __name__ == "__main__":
    import sys
    for filename in sys.argv[1:]:
        package = read_deb(filename)
        print(filename)
        print(package["control"]["control"][0].decode())
        for name, (data, mode) in package["data"].items():
            print(oct(mode), name, f"{len(data)} bytes" if isinstance(data, bytes) else f"-> {data}")
