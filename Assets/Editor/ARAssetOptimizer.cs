#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace OHDMuseum.Editor
{
    /// <summary>
    /// Reversible, Android-only import optimization for artwork textures.
    /// Source image files and their Unity GUIDs are never changed.
    /// </summary>
    public static class ARAssetOptimizer
    {
        private const string PaintingsPath = "Assets/Paintings";
        private const string AndroidPlatform = "Android";
        private const int BalancedMaxTextureSize = 1024;
        private const int BalancedCompressionQuality = 65;
        private const TextureImporterFormat BalancedFormat = TextureImporterFormat.ASTC_4x4;

        [MenuItem("Tools/OHD Museum/Asset Optimization/Analyze Painting Textures")]
        public static void AnalyzePaintingTextures()
        {
            List<TextureImporter> importers = FindPaintingTextureImporters();
            double sourceBytes = importers.Sum(item => GetSourceFileBytes(item.assetPath));
            int androidOverrides = importers.Count(item => item.GetPlatformTextureSettings(AndroidPlatform).overridden);

            Debug.Log(
                $"OHD Museum texture analysis: {importers.Count} textures, " +
                $"{sourceBytes / 1024d / 1024d:F1} MB of source images, " +
                $"{androidOverrides} Android import overrides.");

            foreach (TextureImporter importer in importers)
            {
                TextureImporterPlatformSettings settings = importer.GetPlatformTextureSettings(AndroidPlatform);
                Debug.Log(
                    $"{importer.assetPath}: source={GetSourceFileBytes(importer.assetPath) / 1024d / 1024d:F2} MB, " +
                    $"Android max={settings.maxTextureSize}, format={settings.format}, overridden={settings.overridden}");
            }
        }

        [MenuItem("Tools/OHD Museum/Asset Optimization/Apply Balanced Android Texture Settings")]
        public static void ApplyBalancedAndroidTextureSettings()
        {
            bool approved = EditorUtility.DisplayDialog(
                "Apply balanced Android texture settings?",
                "All textures under Assets/Paintings will use a 1024 px Android limit and ASTC 4x4 compression. " +
                "Source files and GUIDs will not change. This can be reversed from the same menu.",
                "Apply",
                "Cancel");

            if (approved)
            {
                ApplyBalancedAndroidTextureSettingsBatch();
            }
        }

        /// <summary>
        /// Entry point for Unity batch-mode execution.
        /// </summary>
        public static void ApplyBalancedAndroidTextureSettingsBatch()
        {
            List<TextureImporter> importers = FindPaintingTextureImporters();
            int changed = 0;

            try
            {
                AssetDatabase.StartAssetEditing();
                foreach (TextureImporter importer in importers)
                {
                    TextureImporterPlatformSettings settings = importer.GetPlatformTextureSettings(AndroidPlatform);
                    if (IsBalanced(settings))
                    {
                        continue;
                    }

                    settings.name = AndroidPlatform;
                    settings.overridden = true;
                    settings.maxTextureSize = BalancedMaxTextureSize;
                    settings.format = BalancedFormat;
                    settings.textureCompression = TextureImporterCompression.Compressed;
                    settings.compressionQuality = BalancedCompressionQuality;
                    settings.crunchedCompression = false;
                    settings.allowsAlphaSplitting = false;
                    importer.SetPlatformTextureSettings(settings);

                    if (AssetDatabase.WriteImportSettingsIfDirty(importer.assetPath))
                    {
                        changed++;
                    }
                }
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
            }

            if (changed > 0)
            {
                AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);
            }

            Debug.Log($"OHD Museum balanced Android settings: updated {changed} of {importers.Count} painting textures.");
        }

        [MenuItem("Tools/OHD Museum/Asset Optimization/Restore Default Android Texture Settings")]
        public static void RestoreDefaultAndroidTextureSettings()
        {
            bool approved = EditorUtility.DisplayDialog(
                "Restore default Android texture settings?",
                "This removes the Android overrides added by the balanced profile. Source files and GUIDs will not change.",
                "Restore",
                "Cancel");

            if (!approved)
            {
                return;
            }

            List<TextureImporter> importers = FindPaintingTextureImporters();
            int changed = 0;

            try
            {
                AssetDatabase.StartAssetEditing();
                foreach (TextureImporter importer in importers)
                {
                    TextureImporterPlatformSettings settings = importer.GetPlatformTextureSettings(AndroidPlatform);
                    if (!settings.overridden)
                    {
                        continue;
                    }

                    importer.ClearPlatformTextureSettings(AndroidPlatform);
                    if (AssetDatabase.WriteImportSettingsIfDirty(importer.assetPath))
                    {
                        changed++;
                    }
                }
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
            }

            if (changed > 0)
            {
                AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport | ImportAssetOptions.ForceUpdate);
            }

            Debug.Log($"OHD Museum Android texture settings: restored {changed} of {importers.Count} painting textures.");
        }

        private static List<TextureImporter> FindPaintingTextureImporters()
        {
            return AssetDatabase.FindAssets("t:Texture2D", new[] { PaintingsPath })
                .Select(AssetDatabase.GUIDToAssetPath)
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .Select(AssetImporter.GetAtPath)
                .OfType<TextureImporter>()
                .ToList();
        }

        private static bool IsBalanced(TextureImporterPlatformSettings settings)
        {
            return settings.overridden &&
                   settings.maxTextureSize == BalancedMaxTextureSize &&
                   settings.format == BalancedFormat &&
                   settings.textureCompression == TextureImporterCompression.Compressed &&
                   settings.compressionQuality == BalancedCompressionQuality &&
                   !settings.crunchedCompression &&
                   !settings.allowsAlphaSplitting;
        }

        private static long GetSourceFileBytes(string assetPath)
        {
            string fullPath = Path.GetFullPath(assetPath);
            return File.Exists(fullPath) ? new FileInfo(fullPath).Length : 0L;
        }
    }
}
#endif
