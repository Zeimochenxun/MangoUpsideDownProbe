"""Targeted regression tests against the exact local package, using stdlib only.

CPU reference calculations do not execute Objective-C, GPU shader code, or iOS.
The source and archive assertions cover the actual produced dylib/package.
"""
from __future__ import annotations

import gzip
import itertools
import lzma
import re
import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import patch_actual_adaptive as patch


def smoothstep(low, high, value):
    fraction = max(0.0, min(1.0, (value - low) / (high - low)))
    return fraction * fraction * (3.0 - 2.0 * fraction)


def highlight(background, packed, patched):
    if packed is None or (patched and packed & 7 == 0):
        return 0.0
    return smoothstep(0.68, 0.92, sum(c * w for c, w in zip(background, (0.2126, 0.7152, 0.0722))))


def backdrop_uv(capture_px, logical_px, displacement=(0.0, 0.0), cover=False, resolution=(120.0, 30.0),
                card_origin=(440.0, 20.0), transform_offset=(0.0, 0.0),
                transform_x=(1.0, 0.0), transform_y=(0.0, 1.0),
                wallpaper_origin=(0.0, 0.0), wallpaper_resolution=(1000.0, 1000.0),
                orientation=1, zoom=1.0):
    # Reference calculation of the existing mapper at the same displacement as greenSample.
    if cover:
        uv = tuple((px + delta) / dimension for px, delta, dimension in zip(capture_px, displacement, resolution))
    else:
        screen = tuple(origin + px + delta for origin, px, delta in zip(card_origin, logical_px, displacement))
        mapped = tuple(transform_offset[i] + screen[0] * transform_x[i] + screen[1] * transform_y[i]
                       for i in range(2))
        uv = tuple((px - origin) / dimension for px, origin, dimension
                   in zip(mapped, wallpaper_origin, wallpaper_resolution))
        if orientation == 2:
            uv = (1.0 - uv[0], 1.0 - uv[1])
        elif orientation == 3:
            uv = (1.0 - uv[1], uv[0])
        elif orientation == 4:
            uv = (uv[1], 1.0 - uv[0])
    return tuple(max(0.0, min(1.0, 0.5 + (component - 0.5) / max(zoom, 0.01))) for component in uv)


def tokens(source):
    return re.findall(r"[A-Za-z_][A-Za-z_0-9]*|[0-9]+(?:\.[0-9]+)?|[^\s]", source)


def choose_backdrop(mapped_rgba, local_rgba):
    return local_rgba[:3] if mapped_rgba[3] < 0.01 else mapped_rgba[:3]


class ActualAdaptivePatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = (ROOT / "inputs" / "AdaptiveColor-0.1.3-original.deb").read_bytes()
        cls.patched, cls.evidence, cls.fragments = patch.patch_package(cls.original)
        cls.original_members = patch.read_ar(cls.original)
        cls.patched_members = patch.read_ar(cls.patched)
        cls.original_data = lzma.decompress(cls.original_members[2].data)
        cls.patched_data = lzma.decompress(cls.patched_members[2].data)
        cls.original_dylib = patch.entry_payload(cls.original_data, patch.get_entry(cls.original_data, patch.DYLIB_NAME))
        cls.patched_dylib = patch.entry_payload(cls.patched_data, patch.get_entry(cls.patched_data, patch.DYLIB_NAME))
        cls.tables = [struct.unpack_from("<8d", cls.original_dylib, offset)
                      for offset in (0x5248, 0x5288, 0x52C8, 0x5308, 0x5348, 0x5388, 0x53C8)]

    def test_exact_input_required_and_corruption_refused(self):
        self.assertEqual(patch.sha256(self.original), patch.BASELINE_SHA256)
        corrupt = bytearray(self.original)
        corrupt[-1] ^= 1
        with self.assertRaisesRegex(ValueError, "SHA256"):
            patch.patch_package(bytes(corrupt))
        corrupt_dylib = bytearray(self.original_dylib)
        corrupt_dylib[0x4000] ^= 1
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            patch.patch_dylib(bytes(corrupt_dylib))

    def test_source_change_is_guard_and_mapper_only(self):
        old_helper = patch.cstring(self.original_dylib, 0x5A3E).decode("ascii")
        expected_helper = old_helper.replace(patch.OLD_GUARD, patch.NEW_GUARD).replace(patch.REMOVED_COMMENT, "")
        self.assertEqual(self.fragments["helper"].decode("ascii"), expected_helper.ljust(4751, " "))
        old_dispersion = patch.cstring(self.original_dylib, 0x5881).decode("ascii")
        expected_dispersion = old_dispersion.replace(
            "float3 miaCenter = src.sample(s, captureUV).rgb;",
            "float4 c=src.sample(s,backdropSampleUV(capturePx,px,dispPx,isCoverSheet,u));\n if(c.a<0.01)c=src.sample(s,captureUV);")
        expected_dispersion = expected_dispersion.replace(
            "float miaBrightEdge = miaHighlightAmount(miaCenter, u.tintColor);", "")
        expected_dispersion = expected_dispersion.replace("miaBrightEdge", "miaHighlightAmount(c.rgb,u.tintColor)")
        expected_dispersion = expected_dispersion.replace("0.01", ".01")
        self.assertEqual(tokens(expected_dispersion), tokens(self.fragments["dispersion"].decode("ascii")))
        for name in ("curved", "flat", "glare"):
            self.assertEqual(self.fragments[name], patch.cstring(self.original_dylib, patch.STRING_SPECS[name][0]))

    def test_master_zero_disables_all_extra_edge_paths(self):
        settings = (0, 2, 4, 4, 3, 2, 2)
        packed = sum(code << (index * 3) for index, code in enumerate(settings))
        self.assertEqual(packed & 7, 0)
        backgrounds = [(value,) * 3 for value in (-1.0, 0.0, 0.001, 0.5, 0.68, 0.8, 0.92, 1.0, 2.0)]
        backgrounds += list(itertools.product((0.0, 0.5, 1.0), repeat=3))
        for background in backgrounds:
            amount = highlight(background, packed, True)
            self.assertEqual(amount, 0.0)
            self.assertEqual(1.0 + 0.6 * amount, 1.0)  # dispersion boost
            self.assertEqual(min(0.14, 0.3 * 0.34 * amount), 0.0)  # additional rim
            self.assertEqual(1.0 - 0.45 * amount, 1.0)  # glare reduction
        self.assertEqual(highlight((1.0, 1.0, 1.0), packed, False), 1.0)

    def test_all_legal_parameter_codes_keep_nonzero_guard_behavior(self):
        # Exhaust all 2**21 transported settings; legal means the existing shader
        # interval/order checks pass. Nonzero configurations retain the exact same
        # highlight return expression, verified above directly in the real string.
        start, end, dark, bright = self.tables[1:5]
        legal_zero = legal_nonzero = 0
        for packed in range(1 << 21):
            if end[(packed >> 6) & 7] <= start[(packed >> 3) & 7] + 0.009:
                continue
            if bright[(packed >> 12) & 7] > dark[(packed >> 9) & 7]:
                continue
            if packed & 7:
                legal_nonzero += 1
                self.assertFalse(packed == 0xFFFFFFFF or (packed & 7) == 0)
            else:
                legal_zero += 1
                self.assertTrue((packed & 7) == 0)
        self.assertEqual(legal_nonzero, 7 * legal_zero)
        self.assertGreater(legal_nonzero, 1000000)
        for code in range(1, 8):
            for luminance in (0.0, 0.2, 0.68, 0.8, 0.92, 1.0):
                self.assertEqual(highlight((luminance,) * 3, code, False),
                                 highlight((luminance,) * 3, code, True))
        self.assertEqual(highlight((1.0,) * 3, None, True), 0.0)

    def test_mapped_top_card_samples_actual_wallpaper_area(self):
        mapped = backdrop_uv((60.0, 15.0), (60.0, 15.0))
        self.assertEqual(mapped, (0.5, 0.03500000000000003))
        local = (0.5, 0.5)
        wallpaper = lambda uv: (1.0,) * 3 if uv[1] > 0.4 else (0.0,) * 3
        self.assertEqual(highlight(wallpaper(local), 6, True), 1.0)
        self.assertEqual(highlight(wallpaper(mapped), 6, True), 0.0)
        self.assertEqual(backdrop_uv((60.0, 15.0), (60.0, 15.0), cover=True), (0.5, 0.5))

    def test_mapper_respects_rotation_zoom_transform_and_clamp(self):
        args = ((60.0, 15.0), (60.0, 15.0))
        uv = backdrop_uv(*args, card_origin=(10.0, 20.0), transform_offset=(5.0, 7.0),
                         transform_x=(0.0, 2.0), transform_y=(3.0, 0.0),
                         wallpaper_origin=(0.0, 0.0), wallpaper_resolution=(1000.0, 1000.0))
        self.assertAlmostEqual(uv[0], 0.110)
        self.assertAlmostEqual(uv[1], 0.147)
        for orientation, expected in ((2, (0.5, 0.965)), (3, (0.965, 0.5)), (4, (0.035, 0.5))):
            actual = backdrop_uv(*args, orientation=orientation)
            for value, wanted in zip(actual, expected):
                self.assertAlmostEqual(value, wanted)
        zoomed = backdrop_uv(*args, zoom=2.0)
        self.assertAlmostEqual(zoomed[1], 0.2675)
        self.assertEqual(backdrop_uv(*args, card_origin=(-10000.0, 10000.0)), (0.0, 1.0))

    def test_dispersion_matches_green_displacement_and_alpha_fallback(self):
        # Original greenScale is always one, even after the dispersion boost.
        for dispersion in (0.0, 0.5, 1.0, 1.6, 10.0, 20.0):
            green_scale = 1.0 - (1.0 - 1.0) * dispersion
            self.assertEqual(green_scale, 1.0)
            for displacement in ((0.0, 0.0), (-12.0, 9.0), (20.0, -7.0)):
                green_displacement = tuple(value * green_scale for value in displacement)
                self.assertEqual(backdrop_uv((60.0, 15.0), (60.0, 15.0), displacement),
                                 backdrop_uv((60.0, 15.0), (60.0, 15.0), green_displacement))
        self.assertAlmostEqual(backdrop_uv((60.0, 15.0), (60.0, 15.0), (20.0, -7.0))[1], 0.028)
        local = (0.0, 0.0, 0.0, 1.0)
        for alpha in (0.0, 0.005, 0.009999):
            # Hidden white RGB in an unavailable mapped sample must not boost edges.
            self.assertEqual(highlight(choose_backdrop((1.0, 1.0, 1.0, alpha), local), 6, True), 0.0)
        for alpha in (0.01, 0.5, 1.0):
            self.assertEqual(highlight(choose_backdrop((1.0, 1.0, 1.0, alpha), local), 6, True), 1.0)
        self.assertEqual(highlight(choose_backdrop((0.0, 0.0, 0.0, 0.0), (1.0, 1.0, 1.0, 1.0)), 6, True), 1.0)

    def test_signature_and_binary_structure_preserved(self):
        old_directory = patch.verify_code_hashes(self.original_dylib)
        new_directory = patch.verify_code_hashes(self.patched_dylib)
        self.assertEqual(old_directory, new_directory)
        self.assertEqual(self.evidence["changed_code_pages"], [5, 6])
        self.assertEqual(len(self.original_dylib), len(self.patched_dylib))
        allowed = [(0x5881, 0x59C1), (0x5A3E, 0x6CCD)]
        for page in (5, 6):
            start = old_directory["offset"] + old_directory["hash_offset"] + page * 32
            allowed.append((start, start + 32))
        for offset, (left, right) in enumerate(zip(self.original_dylib, self.patched_dylib)):
            if left != right:
                self.assertTrue(any(start <= offset < end for start, end in allowed), hex(offset))
        # Includes every CFString record, not only the five exported strings.
        self.assertEqual(self.original_dylib[0x8180:0x8640], self.patched_dylib[0x8180:0x8640])
        self.assertEqual(self.original_dylib[0x4000:0x4D88], self.patched_dylib[0x4000:0x4D88])
        for _, (offset, length, _) in patch.STRING_SPECS.items():
            self.assertEqual(self.patched_dylib[offset + length], 0)
            self.assertEqual(len(patch.cstring(self.patched_dylib, offset)), length)

    def test_other_files_tar_metadata_and_control_fields_preserved(self):
        for label in ("data_tar", "control_tar"):
            self.assertTrue(self.evidence[label]["metadata_preserved"])
        for left, right in zip(patch.tar_entries(self.original_data), patch.tar_entries(self.patched_data)):
            attributes = ("name", "size", "mode", "uid", "gid", "uname", "gname", "mtime", "type", "linkname",
                          "offset", "offset_data", "pax_headers")
            self.assertEqual(tuple(getattr(left, name) for name in attributes),
                             tuple(getattr(right, name) for name in attributes))
            if patch.normalized_name(left.name) != patch.DYLIB_NAME:
                self.assertEqual(patch.entry_payload(self.original_data, left), patch.entry_payload(self.patched_data, right))
        old_control_tar = gzip.decompress(self.original_members[1].data)
        new_control_tar = gzip.decompress(self.patched_members[1].data)
        old_control = patch.entry_payload(old_control_tar, patch.get_entry(old_control_tar, "control"))
        new_control = patch.entry_payload(new_control_tar, patch.get_entry(new_control_tar, "control"))
        self.assertEqual(new_control.replace(f"Version: {patch.VERSION}\n".encode(), b"Version: 0.1.3\n"), old_control)
        self.assertIn(b"Depends: mobilesubstrate, firmware (= 16.5), com.chenxun.mangoidleisland (>= 1.1.5)\n", new_control)

    def test_package_rebuild_is_deterministic_and_marker_protocol_preserved(self):
        rebuilt, _, _ = patch.patch_package(self.original)
        self.assertEqual(rebuilt, self.patched)
        before = patch.cstring(self.original_dylib, 0x5A3E).decode()
        after = self.fragments["helper"].decode()
        marker_start = before.index("uint miaMarkerAlpha(")
        marker_end = before.index("float miaHighlightAmount(")
        self.assertEqual(before[marker_start:marker_end], after[marker_start:marker_end])


if __name__ == "__main__":
    unittest.main(verbosity=2)
