#!/usr/bin/env python3
"""Shrinks a Meshy GLB for the game: every embedded texture is resized to at
most --size px (base colour kept PNG, the rest JPEG), the mesh is left as is.

  tools/pack_meshy_glb.py IN.glb OUT.glb [--size 1024]
"""
import argparse
import io
import json
import struct

from PIL import Image


def read_glb(path):
    data = open(path, "rb").read()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    offset = 12
    doc, binary = None, b""
    while offset < len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8 : offset + 8 + size]
        if kind == 0x4E4F534A:
            doc = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    return doc, binary


def write_glb(path, doc, binary):
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, default=1024)
    args = ap.parse_args()
    doc, binary = read_glb(args.src)
    base_images = set()
    for m in doc.get("materials", []):
        tex = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex is not None:
            base_images.add(doc["textures"][tex["index"]]["source"])
    images = {}
    for i, img in enumerate(doc.get("images", [])):
        view = doc["bufferViews"][img["bufferView"]]
        start = view.get("byteOffset", 0)
        pic = Image.open(io.BytesIO(binary[start : start + view["byteLength"]]))
        pic.load()
        if max(pic.size) > args.size:
            pic = pic.resize((args.size, args.size), Image.LANCZOS)
        out = io.BytesIO()
        if i in base_images:
            pic.save(out, "PNG", optimize=True)
            img["mimeType"] = "image/png"
        else:
            pic.convert("RGB").save(out, "JPEG", quality=90)
            img["mimeType"] = "image/jpeg"
        images[img["bufferView"]] = out.getvalue()
    # Rebuild the buffer: views in order, images replaced, 4-byte aligned.
    new = bytearray()
    for v, view in enumerate(doc["bufferViews"]):
        start = view.get("byteOffset", 0)
        blob = images.get(v, binary[start : start + view["byteLength"]])
        new += b"\0" * (-len(new) % 4)
        view["byteOffset"] = len(new)
        view["byteLength"] = len(blob)
        new += blob
    doc["buffers"] = [{"byteLength": len(new)}]
    write_glb(args.dst, doc, bytes(new))


if __name__ == "__main__":
    main()
