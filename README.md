# Aerial Image Fader

`aerialfade` fades aerial JPG images used by DWG-based CAD packages and can restore originals.

## Files

- `aerialfade.ps1`: main script
- `aerialfade.cmd`: wrapper so you can run `aerialfade ...` directly on Windows

## Requirements

- Windows PowerShell
- ImageMagick installed and available on `PATH` as `magick`

## Usage

Run from this folder:

```powershell
.\aerialfade.cmd <input> <action>
```

Or if this folder is on your `PATH`:

```powershell
aerialfade <input> <action>
```

### Input

- A DWG path, e.g. `auckland-0075m-urban-aerial-photos-2024-2025.dwg`
- A folder path containing JPG/JPEG files
- A DWG basename without extension (script will try `<name>.dwg`)

When input is a DWG, the script operates on the sibling folder with the same basename.

### Action

- `1` to `100`: fade percentage (higher means more fade to white)
- `0`: restore originals
- `restore`: restore originals

## Examples

```powershell
aerialfade auckland-0075m-urban-aerial-photos-2024-2025.dwg 60
aerialfade auckland-0075m-urban-aerial-photos-2024-2025 50
aerialfade auckland-0075m-urban-aerial-photos-2024-2025 restore
aerialfade auckland-0075m-urban-aerial-photos-2024-2025 0
```

## Behavior

1. Validates target folder has JPG/JPEG files.
2. Creates `original` backup folder on first fade and copies original JPG/JPEG files.
3. Applies fade with ImageMagick in-place.
4. On `restore`/`0`, copies JPG/JPEG files from `original` back to working folder.

## Errors

The script fails with clear messages for:

- Invalid input path
- Target folder without JPG/JPEG files
- Missing ImageMagick (`magick` not found)
- Restore requested but `original` folder or backup JPG/JPEG files are missing
