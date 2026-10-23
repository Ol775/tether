# Catalog format

`Sources/TetherCore/Resources/catalog.json` is the bundled debloat list. A refreshed copy
(validated, `https` only) can supersede it from `~/Library/Application Support/Tether/`.

```json
{ "version": 1, "entries": [ {
  "package": "com.example.app",
  "vendors": ["samsung"],          // lowercase manufacturers; "*" = any
  "platforms": ["fireOS"],         // optional: android | fireOS
  "tier": "recommended",           // safe | recommended | advanced | expert
  "title": "Human name",
  "description": "What it does.",
  "breaks": "What stops working.", // required for advanced and expert
  "source": "where the claim came from"
} ] }
```

Validation rejects: invalid package names, duplicate package+vendor, empty
title/description/source, advanced/expert without `breaks`, unknown versions.

## Provenance

The starter set is drawn from widely repeated community debloat lists and is **not yet
verified on a device**. Universal Android Debloater Next Generation is GPL-3.0, so its data
is not copied here; use it as a cross-check only. Promote an entry's confidence by testing it
on a real device (see `device-checklist.md`) and recording that in `source`.
