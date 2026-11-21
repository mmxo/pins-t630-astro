#!/bin/bash
python3 - << 'PY_EOF'
import glob, re

for fn in sorted(glob.glob("/home/hase/test-fits/*.fits")):
    with open(fn, "rb") as f:
        data = bytearray(f.read())
    pix = 3.76
    for off in range(0, len(data), 80):
        card = data[off:off+80]
        if card.startswith(b"XPIXSZ  ="):
            m = re.search(rb"=\s*([0-9.]+)", card)
            if m:
                pix = float(m.group(1))
        if card.startswith(b"PIXSIZE1"):
            print("Bereits OK:", fn)
            break
        if card.startswith(b"END     "):
            new_card = f"{'PIXSIZE1':<8}= {pix:>20} / Pixel size in microns{'':<30}"[:80].encode("ascii")
            data[off:off+80] = new_card
            if (off + 80) % 2880 == 0:
                data[off+80:off+80] = b"END" + b" " * 77 + b" " * (2880 - 80)
            else:
                data[off+80:off+160] = b"END" + b" " * 77
            with open(fn, "wb") as f:
                f.write(data)
            print(f"PIXSIZE1={pix} ergänzt in:", fn)
            break
PY_EOF
