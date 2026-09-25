# AR asset optimization

The project uses two repeatable optimization paths. Neither path renames assets, so Unity GUIDs and scene/prefab references remain intact.

## Videos

Preview the balanced video profile:

```powershell
.\Tools\Optimize-VideoAssets.ps1
```

Apply it (requires FFmpeg on `PATH`):

```powershell
.\Tools\Optimize-VideoAssets.ps1 -Apply -Profile Balanced
```

The balanced profile caps the long edge at 1280 px, uses H.264 CRF 23, converts audio to AAC at 96 kbps, and only replaces a file when the result is smaller and passes validation. Originals are stored in a timestamped folder under `_video_backup/`. A SHA-256 manifest prevents a later run from re-encoding an unchanged file that was already optimized by the same profile.

Note: re-running with a different profile is intended (each profile has its own manifest, and the backup folder keeps the pre-run files), so `Smallest` can be applied on top of an earlier `Balanced` run as was done for this build.

Available profiles:

- `Smallest`: 960 px, CRF 26, 64 kbps audio
- `Balanced`: 1280 px, CRF 23, 96 kbps audio
- `HighQuality`: 1920 px, CRF 20, 128 kbps audio

## Android painting textures

In Unity, use:

- **Tools > OHD Museum > Asset Optimization > Analyze Painting Textures**
- **Tools > OHD Museum > Asset Optimization > Apply Balanced Android Texture Settings**
- **Tools > OHD Museum > Asset Optimization > Restore Default Android Texture Settings**

The balanced texture profile applies only to Android builds:

- Maximum size: 1024 px
- Format: ASTC 4x4
- Compression quality: 65
- Source image files are unchanged

The source files remain available at their original resolution for future high-quality exports.

### NPOT + mipmaps fallback (root cause of RGBA32 paintings)

Unity silently falls back to uncompressed RGBA32 when a texture is **non-power-of-two after import and has mipmaps enabled**, even when the Android override asks for ASTC 4x4. This affected 38 paintings (NPOT sizes such as 1024x775) and cost 126 MB of build size versus 24 MB for ASTC.

Evidence from the 1.0 build (168 textures): every texture with `nPOTScale: None` + `enableMipMap: 1` imported as RGBA32; the same NPOT sources with `enableMipMap: 0` imported as ASTC 4x4; power-of-two textures imported as ASTC regardless of mipmaps.

Resolution applied: on the affected painting `.meta` files set `enableMipMap: 0`, `wrapU/V/W: 1` (Clamp) and `alphaIsTransparency: 1`, matching the paintings that already imported correctly. Mipmaps are not useful for these AR quads (viewed roughly 1:1, never minified), so no visible quality is lost. Expected saving: ~100 MB per Android build.

If new paintings are added and appear uncompressed in the build report, check this trio of settings first. Quick audit (from the project root, with the build report texture list handy):

```powershell
Select-String -Path 'Assets\Paintings\**\*.meta' -Pattern 'enableMipMap: 1' | Where-Object {
  (Get-Content $_.Path -Raw) -match 'nPOTScale: 0'
}
```
