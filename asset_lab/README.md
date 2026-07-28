# Asset Lab

Asset Lab keeps each asset in a stable toolkit folder and uses manifest metadata
for flexible organization. Do not create taxonomy directories inside
`lab_assets/<type>/`; the canonical path remains:

```text
lab_assets/props/<asset_id>/
lab_assets/characters/<asset_id>/
lab_assets/backgrounds/<asset_id>/
lab_assets/effects/<asset_id>/
```

## Dynamic groups

Use the canonical `groups` field for arbitrary nested virtual folders:

```json
"groups": ["vehicles/cars/XL"]
```

Other valid examples include `vehicles/bikes`, `animals/dogs`, and
`fantasy/forest/backgrounds`. Groups are normalized to safe lowercase path
segments. An asset may belong to more than one group.

The browser creates groupings dynamically from the manifest. New groups do not
need pre-created directories or UI code.

For generated assets, pass groups during creation:

```cmd
python asset_lab/helpers/create_lab_asset.py create-new --type prop --provider self --name car_xl_04 --prompt "..." --group vehicles/cars/XL
```

Repeat `--group` when an asset belongs to multiple collections. Legacy
`domain`, `subcategory`, and `size_class` fields remain readable for migration,
but new mappings should use `groups`.

For repeated reviewed variants, mappings may use `generated_assets` with an
`asset_id_template`, `source_template`, `variant_values`, and `frame_values`.
This keeps numbered families such as bikes explicit and reproducible without
hand-writing duplicate mapping records.

## Intake and validation

For reviewed legacy files, add `groups` to the mapping and use the legacy
importer. Use a dry run first:

```cmd
python asset_lab/helpers/import_legacy_assets.py --mapping asset_lab/legacy_mappings/motocrotte/index.json --asset-id ASSET_ID --dry-run
python asset_lab/helpers/import_legacy_assets.py --mapping asset_lab/legacy_mappings/motocrotte/index.json --asset-id ASSET_ID
```

Validate and refresh the browser manifest after changes:

```cmd
python asset_lab/helpers/validate_lab_assets.py
python asset_lab/helpers/export_browser_manifest.py
```

## Legacy audio and fonts

Legacy project audio with unknown licensing must use
`import_legacy_audio.py`, not the external licensed-candidate importer. The
helper copies the file into `audio_library/imported/`, records its original
source path and SHA-256, and keeps `license: unknown` until provenance is
confirmed.

Fonts are staged separately under `font_library/imported/` because fonts are
not an Asset Lab image/audio type. Love2D can load OTF and TTF files with
`love.graphics.newFont`. Confirm the actual filename before wiring it into the
game; never silently substitute a missing font variant.

Validation checks group syntax, duplicate normalization, referenced files,
animation metadata, and orphan files. Promotion preserves groups in the
runtime manifest, while runtime file paths remain type-based and stable.

## Browser workflow

Use the sidebar search field to filter by asset ID, group, source path, or
animation name. Use `Collapse` and `Expand` to manage the taxonomy tree. When
an asset has a GIF animation, selecting it opens the GIF preview by default;
use the inspector's `Sprite sheet` button to inspect the source sheet.
