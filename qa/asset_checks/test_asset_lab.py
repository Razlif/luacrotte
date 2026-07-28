from __future__ import annotations

import base64
import json
import os
import sys
import tempfile
import unittest
import urllib.error
import urllib.request
from io import BytesIO
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPERS_DIR = REPO_ROOT / "asset_lab" / "helpers"
PROVIDERS_DIR = HELPERS_DIR / "providers"
sys.path.insert(0, str(HELPERS_DIR))
sys.path.insert(0, str(PROVIDERS_DIR))

import common
import create_lab_asset
import manifest
import sync_manifest
import validate_lab_assets
import autosprite
import pixellab
import audio_manifest
import audio_search
import audio_import
import promote_audio_asset


def make_png(path: Path, color: tuple[int, int, int, int] = (255, 0, 0, 255)) -> None:
    from PIL import Image

    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGBA", (8, 8), color).save(path)


def make_gif(path: Path) -> None:
    from PIL import Image

    path.parent.mkdir(parents=True, exist_ok=True)
    frames = [
        Image.new("RGBA", (8, 8), (255, 0, 0, 255)),
        Image.new("RGBA", (8, 8), (0, 255, 0, 255)),
    ]
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=120, loop=0)


def png_base64(color: tuple[int, int, int, int] = (0, 255, 0, 255)) -> str:
    from PIL import Image

    buffer = BytesIO()
    Image.new("RGBA", (8, 8), color).save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


class TempAssetLab:
    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.lab = Path(self.tmp.name) / "asset_lab"
        self.assets = self.lab / "lab_assets"
        self.assets.mkdir(parents=True)
        self.manifest_path = self.lab / "manifest.json"
        self.manifest_path.write_text("{}\n", encoding="utf-8")

        self.originals = {
            "common_lab": common.ASSET_LAB_DIR,
            "common_assets": common.LAB_ASSETS_DIR,
            "common_manifest": common.MANIFEST_PATH,
            "manifest_path": manifest.MANIFEST_PATH,
            "validator_lab": validate_lab_assets.ASSET_LAB_DIR,
            "validator_assets": validate_lab_assets.LAB_ASSETS_DIR,
        }
        common.ASSET_LAB_DIR = self.lab
        common.LAB_ASSETS_DIR = self.assets
        common.MANIFEST_PATH = self.manifest_path
        manifest.MANIFEST_PATH = self.manifest_path
        validate_lab_assets.ASSET_LAB_DIR = self.lab
        validate_lab_assets.LAB_ASSETS_DIR = self.assets
        return self

    def __exit__(self, *_):
        common.ASSET_LAB_DIR = self.originals["common_lab"]
        common.LAB_ASSETS_DIR = self.originals["common_assets"]
        common.MANIFEST_PATH = self.originals["common_manifest"]
        manifest.MANIFEST_PATH = self.originals["manifest_path"]
        validate_lab_assets.ASSET_LAB_DIR = self.originals["validator_lab"]
        validate_lab_assets.LAB_ASSETS_DIR = self.originals["validator_assets"]
        self.tmp.cleanup()


def run_cli(*args: str) -> int:
    old_argv = sys.argv[:]
    try:
        sys.argv = ["create_lab_asset.py", *args]
        return create_lab_asset.main()
    finally:
        sys.argv = old_argv


class AssetLabCliTests(unittest.TestCase):
    def test_dynamic_groups_are_normalized_and_created_without_disk_subfolders(self) -> None:
        self.assertEqual(common.normalize_groups(["Vehicles/Cars/XL", "animals/dogs"]), ["animals/dogs", "vehicles/cars/xl"])
        with self.assertRaises(ValueError):
            common.normalize_groups(["animals/../dogs"])

        with TempAssetLab() as lab:
            self.assertEqual(
                run_cli(
                    "create-new", "--type", "prop", "--provider", "self", "--name", "dog",
                    "--prompt", "friendly dog", "--group", "animals/dogs", "--execute"
                ),
                0,
            )
            asset = manifest.find_asset("dog", "prop")
            self.assertEqual(asset["groups"], ["animals/dogs"])
            self.assertEqual(asset["folder"], "lab_assets/props/dog")
            self.assertFalse((lab.assets / "props" / "animals" / "dogs").exists())

    def test_full_mock_flow_and_validation(self) -> None:
        with TempAssetLab() as lab:
            image_one = lab.lab / "fixtures" / "one.png"
            image_two = lab.lab / "fixtures" / "two.png"
            frames_dir = lab.lab / "fixtures" / "frames"
            make_png(image_one)
            make_png(image_two, (0, 0, 255, 255))
            make_png(frames_dir / "frame_00.png")
            make_png(frames_dir / "frame_01.png", (0, 255, 0, 255))

            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "mock", "--name", "test_duck", "--prompt", "mock", "--mock-image", str(image_one), "--execute"), 0)
            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "mock", "--name", "test_duck", "--prompt", "dupe", "--mock-image", str(image_one), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "test_duck", "--mode", "brand_new", "--prompt", "redraw", "--mock-image", str(image_two), "--variation-group-id", "duck_redraw_batch", "--execute"), 0)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "test_duck", "--mode", "with_reference", "--source-image-version", "v002", "--init-image-strength", "650", "--prompt", "variation", "--mock-image", str(image_two), "--variation-group-id", "duck_reference_batch", "--execute"), 0)
            self.assertEqual(run_cli("create-animation", "--type", "character", "--provider", "mock", "--name", "test_duck", "--animation", "jump", "--source-image-version", "v003", "--prompt", "jump", "--mock-frames-dir", str(frames_dir), "--variation-group-id", "duck_jump_batch", "--execute"), 0)

            self.assertEqual(validate_lab_assets.main(), 0)
            asset = manifest.find_asset("test_duck", "character")
            self.assertEqual(len(asset["images"]), 3)
            self.assertEqual(asset["images"][-1]["mode"], "with_reference")
            self.assertEqual(asset["images"][-1]["source_image_version"], 2)
            self.assertEqual(asset["images"][1]["variation_group_id"], "duck_redraw_batch")
            self.assertEqual(asset["images"][1]["prompt_metadata"]["asset_type"], "character")
            self.assertEqual(asset["images"][1]["prompt_metadata"]["mode"], "brand_new")
            self.assertEqual(asset["images"][-1]["variation_group_id"], "duck_reference_batch")
            self.assertEqual(asset["images"][-1]["prompt_metadata"]["source_prompt_snapshot"], "redraw")
            self.assertEqual(asset["animations"][0]["source_image_version"], 3)
            self.assertEqual(asset["animations"][0]["variation_group_id"], "duck_jump_batch")
            self.assertEqual(asset["animations"][0]["prompt_metadata"]["source_prompt_snapshot"], "variation")
            self.assertEqual(asset["animations"][0]["prompt_metadata"]["animation"], "jump")

    def test_cli_blocks_drift_and_bad_inputs(self) -> None:
        with TempAssetLab() as lab:
            image = lab.lab / "fixtures" / "one.png"
            frames_dir = lab.lab / "fixtures" / "frames"
            make_png(image)
            make_png(frames_dir / "frame_00.png")

            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--prompt", "mock", "--mock-image", str(image), "--execute"), 0)
            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "mock", "--name", "drift_duc", "--prompt", "typo", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "prop", "--provider", "mock", "--name", "drift_duck", "--mode", "brand_new", "--prompt", "wrong", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "missing_duck", "--mode", "brand_new", "--prompt", "missing", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--mode", "brand_new", "--source-image-version", "v001", "--prompt", "bad", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--mode", "with_reference", "--prompt", "bad", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("add-image-version", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--mode", "with_reference", "--source-image-version", "v001", "--init-image-strength", "1000", "--prompt", "bad", "--mock-image", str(image), "--execute"), 2)
            self.assertEqual(run_cli("create-animation", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--animation", "jump", "--source-image-version", "bananas", "--prompt", "bad", "--mock-frames-dir", str(frames_dir), "--execute"), 2)
            self.assertEqual(run_cli("create-animation", "--type", "character", "--provider", "mock", "--name", "drift_duck", "--animation", "jump", "--source-image-version", "v009", "--prompt", "bad", "--mock-frames-dir", str(frames_dir), "--execute"), 2)

    def test_dry_run_does_not_change_manifest(self) -> None:
        with TempAssetLab() as lab:
            before = lab.manifest_path.read_text(encoding="utf-8")
            self.assertEqual(run_cli("create-new", "--type", "effect", "--provider", "pixellab", "--name", "dry_effect", "--prompt", "small magic poof"), 0)
            after = lab.manifest_path.read_text(encoding="utf-8")
            self.assertEqual(before, after)

    def test_self_provider_create_new_is_pending_until_file_exists(self) -> None:
        with TempAssetLab() as lab:
            self.assertEqual(run_cli("create-new", "--type", "effect", "--provider", "self", "--name", "magic_poof", "--prompt", "tiny magic poof", "--execute"), 0)
            self.assertEqual(validate_lab_assets.main(), 1)

            asset = manifest.find_asset("magic_poof", "effect")
            self.assertEqual(asset["images"][0]["status"], "pending_self_creation")
            self.assertEqual(asset["images"][0]["prompt_metadata"]["provider"], "self")
            make_png(lab.lab / asset["images"][0]["path"])

            self.assertEqual(validate_lab_assets.main(), 0)
            data = manifest.load_manifest()
            self.assertEqual(sync_manifest.mark_missing_references(data), 1)
            manifest.save_manifest(data)
            asset = manifest.find_asset("magic_poof", "effect")
            self.assertEqual(asset["images"][0]["status"], "created_on_disk")

    def test_self_provider_with_reference_and_animation_paths(self) -> None:
        with TempAssetLab() as lab:
            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "self", "--name", "self_duck", "--prompt", "duck v1", "--execute"), 0)
            asset = manifest.find_asset("self_duck", "character")
            make_png(lab.lab / asset["images"][0]["path"])
            self.assertEqual(validate_lab_assets.main(), 0)

            self.assertEqual(
                run_cli(
                    "add-image-version",
                    "--type",
                    "character",
                    "--provider",
                    "self",
                    "--name",
                    "self_duck",
                    "--mode",
                    "with_reference",
                    "--source-image-version",
                    "v001",
                    "--prompt",
                    "duck v2 with taller hat",
                    "--execute",
                ),
                0,
            )
            self.assertEqual(validate_lab_assets.main(), 1)
            asset = manifest.find_asset("self_duck", "character")
            self.assertEqual(asset["images"][1]["source_image_version"], 1)
            make_png(lab.lab / asset["images"][1]["path"], (0, 0, 255, 255))
            self.assertEqual(validate_lab_assets.main(), 0)

            self.assertEqual(run_cli("create-animation", "--type", "character", "--provider", "self", "--name", "self_duck", "--animation", "jump", "--source-image-version", "v002", "--frame-count", "4", "--fps", "8", "--prompt", "jump spritesheet", "--execute"), 0)
            self.assertEqual(validate_lab_assets.main(), 1)
            asset = manifest.find_asset("self_duck", "character")
            make_png(lab.lab / asset["animations"][0]["sheet_path"], (255, 255, 0, 255))
            make_gif(lab.lab / asset["animations"][0]["gif_path"])
            self.assertEqual(validate_lab_assets.main(), 0)
            data = manifest.load_manifest()
            self.assertEqual(sync_manifest.mark_missing_references(data), 3)
            manifest.save_manifest(data)
            asset = manifest.find_asset("self_duck", "character")
            self.assertEqual(asset["animations"][0]["status"], "created_on_disk")

    def test_validator_finds_manifest_drift(self) -> None:
        with TempAssetLab() as lab:
            data = {
                "version": 1,
                "assets": [
                    {
                        "id": "missing_duck",
                        "type": "character",
                        "folder": "lab_assets/characters/missing_duck",
                        "images": [{"id": "img", "version": 1, "path": "lab_assets/characters/missing_duck/original_images/missing.png"}],
                        "animations": [{"id": "anim", "name": "jump", "source_image_version": 2, "sheet_path": "missing_sheet.png", "gif_path": "missing.gif"}],
                        "provider_state": {"autosprite": {"source_image_version": None}},
                    }
                ],
            }
            lab.manifest_path.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(validate_lab_assets.main(), 1)

    def test_sync_manifest_marks_missing_and_registers_orphans(self) -> None:
        with TempAssetLab() as lab:
            image = lab.lab / "fixtures" / "one.png"
            make_png(image)
            self.assertEqual(run_cli("create-new", "--type", "character", "--provider", "mock", "--name", "sync_duck", "--prompt", "mock", "--mock-image", str(image), "--execute"), 0)
            asset = manifest.find_asset("sync_duck", "character")
            referenced_path = lab.lab / asset["images"][0]["path"]
            referenced_path.unlink()

            orphan_path = lab.assets / "characters" / "sync_duck" / "original_images" / "loose_orphan.png"
            make_png(orphan_path)

            data = manifest.load_manifest()
            missing = sync_manifest.find_missing_references(data)
            orphans = sync_manifest.find_orphan_files(data)
            self.assertEqual(len(missing), 1)
            self.assertEqual(orphans, ["lab_assets/characters/sync_duck/original_images/loose_orphan.png"])

            self.assertEqual(sync_manifest.mark_missing_references(data), 1)
            self.assertEqual(sync_manifest.sync_orphans(data, orphans), 1)
            manifest.save_manifest(data)

            updated = manifest.load_manifest()
            updated_asset = updated["assets"][0]
            self.assertEqual(updated_asset["images"][0]["status"], "missing_on_disk")
            self.assertEqual(updated["orphans"][0]["status"], "orphan_on_disk")
            self.assertEqual(validate_lab_assets.validate_orphans(updated), [])
            self.assertEqual(validate_lab_assets.main(), 1)

    def test_sync_manifest_marks_old_orphan_missing(self) -> None:
        with TempAssetLab() as lab:
            orphan_path = lab.assets / "effects" / "loose" / "original_images" / "spark.png"
            make_png(orphan_path)
            data = manifest.load_manifest()
            orphans = sync_manifest.find_orphan_files(data)
            sync_manifest.sync_orphans(data, orphans)
            manifest.save_manifest(data)

            orphan_path.unlink()
            data = manifest.load_manifest()
            self.assertEqual(sync_manifest.sync_orphans(data, sync_manifest.find_orphan_files(data)), 1)
            self.assertEqual(data["orphans"][0]["status"], "orphan_missing_on_disk")

    def test_sync_manifest_backfills_prompt_metadata(self) -> None:
        with TempAssetLab() as lab:
            data = {
                "version": 1,
                "assets": [
                    {
                        "id": "legacy_duck",
                        "type": "character",
                        "folder": "lab_assets/characters/legacy_duck",
                        "images": [{"id": "legacy_duck__mock__image__v001", "provider": "mock", "version": 1, "path": "x.png", "prompt": "duck prompt"}],
                        "animations": [{"id": "legacy_duck__mock__jump_from_image_v001__v001", "provider": "mock", "name": "jump", "source_image_version": 1, "sheet_path": "sheet.png", "gif_path": "anim.gif", "prompt": "jump prompt"}],
                    }
                ],
            }
            self.assertEqual(sync_manifest.backfill_prompt_metadata(data), 2)
            asset = data["assets"][0]
            self.assertEqual(asset["images"][0]["prompt_metadata"]["asset_type"], "character")
            self.assertEqual(asset["images"][0]["prompt_metadata"]["action"], "legacy_image")
            self.assertEqual(asset["animations"][0]["prompt_metadata"]["source_prompt_snapshot"], "duck prompt")


class AudioAssetTests(unittest.TestCase):
    def test_license_policy_normalizes_allowed_and_rejects_restricted(self) -> None:
        self.assertTrue(audio_manifest.license_allowed("Creative Commons 0"))
        self.assertTrue(audio_manifest.license_allowed("https://creativecommons.org/licenses/by/4.0/"))
        self.assertFalse(audio_manifest.license_allowed("Attribution NonCommercial"))
        self.assertFalse(audio_manifest.license_allowed(None))

    def test_curated_candidates_require_allowed_license(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "curated.json"
            path.write_text(json.dumps({
                "source": "kenney", "kind": "sound", "title": "Jump", "license": "CC0",
                "source_url": "https://kenney.nl/assets"
            }), encoding="utf-8")
            candidate = audio_search.curated_candidates(path)[0]
            self.assertEqual(candidate["candidate_id"], "kenney_jump")
            path.write_text(json.dumps({
                "source": "oga", "kind": "sound", "title": "Restricted", "license": "CC BY-NC",
                "source_url": "https://opengameart.org/"
            }), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "disallowed"):
                audio_search.curated_candidates(path)

    def test_audio_import_and_promotion_update_runtime_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lab = root / "asset_lab"
            imported = lab / "audio_library" / "imported" / "sound" / "magic_explosion.ogg"
            imported.parent.mkdir(parents=True)
            imported.write_bytes(b"mock ogg")
            catalog = {"version": 1, "candidates": [{
                "candidate_id": "freesound_123", "kind": "sound", "source": "freesound",
                "source_id": "123", "title": "Magic Explosion", "author": "Artist",
                "license": "CC0", "source_url": "https://freesound.org/s/123/",
                "local_preview": "audio_library/previews/freesound_123.ogg",
                "imported_path": "audio_library/imported/sound/magic_explosion.ogg",
                "status": "imported"
            }]}
            lab.joinpath("audio_library").mkdir(exist_ok=True)
            lab.joinpath("audio_library", "catalog.json").write_text(json.dumps(catalog), encoding="utf-8")
            original = {
                "audio_lab": audio_manifest.ASSET_LAB_DIR,
                "catalog": audio_manifest.CATALOG_PATH,
                "imported": audio_manifest.IMPORTED_DIR,
                "root": promote_audio_asset.PROJECT_ROOT,
                "credits": promote_audio_asset.ATTRIBUTIONS_PATH,
            }
            try:
                audio_manifest.ASSET_LAB_DIR = lab
                audio_manifest.CATALOG_PATH = lab / "audio_library" / "catalog.json"
                audio_manifest.IMPORTED_DIR = lab / "audio_library" / "imported"
                promote_audio_asset.PROJECT_ROOT = root
                promote_audio_asset.ATTRIBUTIONS_PATH = root / "media_assets" / "audio" / "ATTRIBUTIONS.json"
                self.assertEqual(promote_audio_asset.main([
                    "--operation", "promote-new", "--kind", "sound", "--asset-id", "magic_explosion",
                    "--candidate-id", "freesound_123"
                ]), 0)
                self.assertFalse((root / "media_assets" / "audio" / "sounds" / "magic_explosion.ogg").exists())
                self.assertEqual(promote_audio_asset.main([
                    "--operation", "promote-new", "--kind", "sound", "--asset-id", "magic_explosion",
                    "--candidate-id", "freesound_123", "--execute"
                ]), 0)
                runtime = (root / "game_data" / "asset_manifest.lua").read_text(encoding="utf-8")
                self.assertIn("magic_explosion", runtime)
                credits = json.loads((root / "media_assets" / "audio" / "ATTRIBUTIONS.json").read_text(encoding="utf-8"))
                self.assertEqual(credits["audio"]["magic_explosion"]["license"], "CC0")
            finally:
                audio_manifest.ASSET_LAB_DIR = original["audio_lab"]
                audio_manifest.CATALOG_PATH = original["catalog"]
                audio_manifest.IMPORTED_DIR = original["imported"]
                promote_audio_asset.PROJECT_ROOT = original["root"]
                promote_audio_asset.ATTRIBUTIONS_PATH = original["credits"]


class PixelLabProviderTests(unittest.TestCase):
    def test_static_payload_brand_new_and_with_reference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "source.png"
            make_png(image)
            brand_new = pixellab.static_payload("duck", 64, 64, False)
            self.assertNotIn("init_images", brand_new)
            with_reference = pixellab.static_payload("duck", 64, 64, False, image, 650)
            self.assertEqual(with_reference["init_image_strength"], 650)
            self.assertEqual(with_reference["init_images"][0]["type"], "base64")

    def test_generate_static_errors_are_clear(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            trace = Path(tmp) / "trace.jsonl"
            with patch.object(pixellab, "request_json", return_value=(402, {"error": "credits"})):
                with self.assertRaisesRegex(RuntimeError, "HTTP 402"):
                    pixellab.generate_static(api_key="key", prompt="x", width=8, height=8, with_background=False, trace_path=trace)
            with patch.object(pixellab, "request_json", return_value=(200, {"image": {}})):
                with self.assertRaisesRegex(RuntimeError, "image.base64"):
                    pixellab.generate_static(api_key="key", prompt="x", width=8, height=8, with_background=False, trace_path=trace)

    def test_generate_animation_success_and_failures(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.png"
            trace = Path(tmp) / "trace.jsonl"
            make_png(source)
            calls = [
                (200, {"background_job_id": "job_1"}),
                (200, {"status": "completed", "last_response": {"images": [{"base64": png_base64()}]}}),
            ]

            def fake_request(*_args, **_kwargs):
                return calls.pop(0)

            with patch.object(pixellab, "request_json", side_effect=fake_request), patch.object(pixellab.time, "sleep", return_value=None):
                result = pixellab.generate_animation(api_key="key", input_image=source, action="jump", frame_count=1, seed=1, trace_path=trace)
                self.assertEqual(len(result["frame_images_base64"]), 1)

            with patch.object(pixellab, "request_json", return_value=(200, {})):
                with self.assertRaisesRegex(RuntimeError, "background_job_id"):
                    pixellab.generate_animation(api_key="key", input_image=source, action="jump", frame_count=1, seed=1, trace_path=trace)


class AutoSpriteProviderTests(unittest.TestCase):
    def test_account_check_success_and_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            trace = Path(tmp) / "trace.jsonl"
            with patch.object(autosprite, "request_json", return_value=(200, {"credits": 15})):
                self.assertEqual(autosprite.check_account(api_key="key", trace_path=trace)["credits"], 15)
            with patch.object(autosprite, "request_json", return_value=(401, {"error": "bad"})):
                with self.assertRaisesRegex(RuntimeError, "HTTP 401"):
                    autosprite.check_account(api_key="key", trace_path=trace)

    def test_character_upload_success_and_errors(self) -> None:
        class FakeResponse:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self):
                return b'{"id":"char_123","baseImageUrl":"https://example.test/base.png","thumbnailUrl":"https://example.test/thumb.png"}'

        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "source.png"
            trace = Path(tmp) / "trace.jsonl"
            make_png(image)
            with patch.object(urllib.request, "urlopen", return_value=FakeResponse()):
                result = autosprite.create_character_from_image(api_key="key", name="duck", image_path=image, character_description="duck", is_humanoid=True, trace_path=trace)
                self.assertEqual(result["id"], "char_123")
            with self.assertRaises(FileNotFoundError):
                autosprite.create_character_from_image(api_key="key", name="duck", image_path=Path(tmp) / "missing.png", character_description="duck", is_humanoid=True, trace_path=trace)


if __name__ == "__main__":
    unittest.main()
