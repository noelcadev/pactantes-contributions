#!/usr/bin/env python3
"""Extract the original 1-bit page scans from the Gredos Confesiones PDF."""

import argparse
from contextlib import closing
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory

from PIL import Image
import pypdfium2
from pypdfium2 import raw


SOURCE_SHA256 = "e9099bdecc37a6bb19f3db1eb8cb956f01d1e98aa8fa1a4822f0b4456986e01b"
BOOK_RANGES = (
    (111, 152), (154, 173), (175, 206), (208, 244), (246, 280),
    (283, 322), (324, 362), (364, 404), (407, 451), (454, 525),
    (528, 568), (571, 612), (615, 670),
)
PAGE_NUMBERS = tuple(
    page for start, end in BOOK_RANGES for page in range(start, end + 1)
)
DEFAULT_SIZE = (1251, 2067)
OTHER_SIZES = {294: (1253, 2067), 295: (1252, 2067), 596: (1283, 2086)}
PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def extract_page(page, number, destination):
    # The opaque scan is drawn last, on top of the OCR text objects.
    # Do not paint the PDF annotations, including the later stamp on page 244.
    objects = list(page.get_objects())
    image = objects[-1]
    if image.type != raw.FPDF_PAGEOBJ_IMAGE or any(
        obj.type != raw.FPDF_PAGEOBJ_TEXT for obj in objects[:-1]
    ):
        raise ValueError(f"Page {number}: unexpected PDF object order")
    a, b, c, d, e, f = image.get_matrix().get()
    width, height = page.get_size()
    if (page.get_rotation() or (b, c, e, f) != (0, 0, 0, 0)
            or abs(a - width) > 0.001 or abs(d - height) > 0.001):
        raise ValueError(f"Page {number}: unexpected scan placement")
    expected_size = OTHER_SIZES.get(number, DEFAULT_SIZE)

    with closing(image.get_bitmap(render=False)) as bitmap:
        original = bitmap.to_pil()
        if original.mode != "L" or original.size != expected_size:
            raise ValueError(f"Page {number}: unexpected scan mode or size")
        histogram = original.histogram()
        if not 0 < histogram[0] < histogram[255] or any(histogram[1:255]):
            raise ValueError(f"Page {number}: scan is empty or not black on white")
        original.convert("1", dither=Image.Dither.NONE).save(
            destination, format="PNG", optimize=True
        )
        with Image.open(destination) as written:
            if (written.mode != "1" or written.size != expected_size
                    or written.convert("L").tobytes() != original.tobytes()):
                raise ValueError(f"Page {number}: PNG changed the source pixels")
    data = destination.read_bytes()
    if data[:8] != PNG_HEADER or data[12:16] != b"IHDR" or data[24:26] != b"\x01\x00":
        raise ValueError(f"Page {number}: expected 1-bit grayscale PNG")
    return sha256(data).hexdigest(), len(data)


def extract(source, output):
    if sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError("Source SHA-256 does not match the expected Gredos PDF")
    if len(PAGE_NUMBERS) != 542 or PAGE_NUMBERS != tuple(sorted(set(PAGE_NUMBERS))):
        raise ValueError("Invalid page range manifest")
    output.mkdir(parents=True, exist_ok=True)
    pages_dir, manifest = output / "pages", output / "SHA256SUMS"
    if pages_dir.exists() or manifest.exists():
        raise FileExistsError(f"Output already exists in {output}")

    with TemporaryDirectory(prefix=".gredos-", dir=output) as temporary:
        staged = Path(temporary)
        checksums = []
        total_bytes = 0
        with closing(pypdfium2.PdfDocument(source)) as document:
            if len(document) != 680:
                raise ValueError("Expected the 680-page Gredos PDF")
            for number in PAGE_NUMBERS:
                filename = f"{number}.png"
                with closing(document[number - 1]) as page:
                    checksum, size = extract_page(page, number, staged / filename)
                checksums.append(f"{checksum}  pages/{filename}\n")
                total_bytes += size
        if {file.name for file in staged.iterdir()} != {
            f"{number}.png" for number in PAGE_NUMBERS
        }:
            raise ValueError("Output does not match the expected pages")
        staged.rename(pages_dir)
    manifest.write_text("".join(checksums), encoding="ascii")
    print(f"Extracted {len(PAGE_NUMBERS)} pages, {total_bytes} bytes")
    print(f"SHA-256 of SHA256SUMS: {sha256(manifest.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_pdf", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    extract(args.input_pdf, args.output_dir)
