pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// Pre-computed palette lookup shared across all BarWidgetPalette instances
// (77+ usages). Evaluates Appearance.colors once per theme change instead of
// creating ~160 reactive dependency captures per bar widget instance.
Singleton {
    id: store

    function normalizeMode(colorMode) {
        const raw = String(colorMode ?? "primary").trim().toLowerCase().replace(/[\s_-]/g, "");
        if (raw === "vibrant") return "primary";
        if (raw === "tonal") return "tertiaryContainer";
        if (raw === "alert") return "alert";
        if (raw === "primary") return "primary";
        if (raw === "primarycontainer") return "primaryContainer";
        if (raw === "secondary") return "secondary";
        if (raw === "secondarycontainer") return "secondaryContainer";
        if (raw === "tertiary" || raw === "teritiary") return "tertiary";
        if (raw === "tertiarycontainer" || raw === "teritiarycontainer") return "tertiaryContainer";
        if (raw === "neutral") return "neutral";
        if (raw === "neutralcontainer") return "neutralContainer";
        return "primary";
    }

    readonly property var palettes: {
        const c = Appearance.colors;
        return {
            "primary": {
                colBackground: c.colPrimary,
                colOnBackground: c.colOnPrimary,
                colBackgroundHover: c.colPrimaryHover,
                colBackgroundActive: c.colPrimaryActive,
                colBackgroundVariant: c.colPrimaryContainer,
                colOnBackgroundVariant: c.colOnPrimaryContainer,
                colBackgroundVariantHover: c.colPrimaryContainerHover,
                colBackgroundVariantActive: c.colPrimaryContainerActive,
                colContainer: c.colPrimaryContainer,
                colOnContainer: c.colOnPrimaryContainer,
                colContainerHover: c.colPrimaryContainerHover,
                colContainerActive: c.colPrimaryContainerActive,
                colAccent: c.colPrimary,
                colOnAccent: c.colOnPrimary,
                colAccentHover: c.colPrimaryHover,
                colAccentActive: c.colPrimaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colPrimary
            },
            "primaryContainer": {
                colBackground: c.colPrimaryContainer,
                colOnBackground: c.colOnPrimaryContainer,
                colBackgroundHover: c.colPrimaryContainerHover,
                colBackgroundActive: c.colPrimaryContainerActive,
                colBackgroundVariant: c.colPrimary,
                colOnBackgroundVariant: c.colOnPrimary,
                colBackgroundVariantHover: c.colPrimaryHover,
                colBackgroundVariantActive: c.colPrimaryActive,
                colContainer: c.colPrimaryContainer,
                colOnContainer: c.colOnPrimaryContainer,
                colContainerHover: c.colPrimaryContainerHover,
                colContainerActive: c.colPrimaryContainerActive,
                colAccent: c.colPrimary,
                colOnAccent: c.colOnPrimary,
                colAccentHover: c.colPrimaryHover,
                colAccentActive: c.colPrimaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colPrimary
            },
            "secondary": {
                colBackground: c.colSecondary,
                colOnBackground: c.colOnSecondary,
                colBackgroundHover: c.colSecondaryHover,
                colBackgroundActive: c.colSecondaryActive,
                colBackgroundVariant: c.colSecondaryContainer,
                colOnBackgroundVariant: c.colOnSecondaryContainer,
                colBackgroundVariantHover: c.colSecondaryContainerHover,
                colBackgroundVariantActive: c.colSecondaryContainerActive,
                colContainer: c.colSecondaryContainer,
                colOnContainer: c.colOnSecondaryContainer,
                colContainerHover: c.colSecondaryContainerHover,
                colContainerActive: c.colSecondaryContainerActive,
                colAccent: c.colSecondary,
                colOnAccent: c.colOnSecondary,
                colAccentHover: c.colSecondaryHover,
                colAccentActive: c.colSecondaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colSecondary
            },
            "secondaryContainer": {
                colBackground: c.colSecondaryContainer,
                colOnBackground: c.colOnSecondaryContainer,
                colBackgroundHover: c.colSecondaryContainerHover,
                colBackgroundActive: c.colSecondaryContainerActive,
                colBackgroundVariant: c.colSecondary,
                colOnBackgroundVariant: c.colOnSecondary,
                colBackgroundVariantHover: c.colSecondaryHover,
                colBackgroundVariantActive: c.colSecondaryActive,
                colContainer: c.colSecondaryContainer,
                colOnContainer: c.colOnSecondaryContainer,
                colContainerHover: c.colSecondaryContainerHover,
                colContainerActive: c.colSecondaryContainerActive,
                colAccent: c.colSecondary,
                colOnAccent: c.colOnSecondary,
                colAccentHover: c.colSecondaryHover,
                colAccentActive: c.colSecondaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colSecondary
            },
            "tertiary": {
                colBackground: c.colTertiary,
                colOnBackground: c.colOnTertiary,
                colBackgroundHover: c.colTertiaryHover,
                colBackgroundActive: c.colTertiaryActive,
                colBackgroundVariant: c.colTertiaryContainer,
                colOnBackgroundVariant: c.colOnTertiaryContainer,
                colBackgroundVariantHover: c.colTertiaryContainerHover,
                colBackgroundVariantActive: c.colTertiaryContainerActive,
                colContainer: c.colTertiaryContainer,
                colOnContainer: c.colOnTertiaryContainer,
                colContainerHover: c.colTertiaryContainerHover,
                colContainerActive: c.colTertiaryContainerActive,
                colAccent: c.colTertiary,
                colOnAccent: c.colOnTertiary,
                colAccentHover: c.colTertiaryHover,
                colAccentActive: c.colTertiaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colTertiary
            },
            "tertiaryContainer": {
                colBackground: c.colTertiaryContainer,
                colOnBackground: c.colOnTertiaryContainer,
                colBackgroundHover: c.colTertiaryContainerHover,
                colBackgroundActive: c.colTertiaryContainerActive,
                colBackgroundVariant: c.colTertiary,
                colOnBackgroundVariant: c.colOnTertiary,
                colBackgroundVariantHover: c.colTertiaryHover,
                colBackgroundVariantActive: c.colTertiaryActive,
                colContainer: c.colTertiaryContainer,
                colOnContainer: c.colOnTertiaryContainer,
                colContainerHover: c.colTertiaryContainerHover,
                colContainerActive: c.colTertiaryContainerActive,
                colAccent: c.colTertiary,
                colOnAccent: c.colOnTertiary,
                colAccentHover: c.colTertiaryHover,
                colAccentActive: c.colTertiaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colTertiary
            },
            "neutral": {
                colBackground: c.colSurfaceContainerHighest,
                colOnBackground: c.colOnSurface,
                colBackgroundHover: c.colSurfaceContainerHighestHover,
                colBackgroundActive: c.colSurfaceContainerHighestActive,
                colBackgroundVariant: c.colSurfaceContainerHigh,
                colOnBackgroundVariant: c.colOnSurface,
                colBackgroundVariantHover: c.colSurfaceContainerHighestHover,
                colBackgroundVariantActive: c.colSurfaceContainerHighestActive,
                colContainer: c.colSurfaceContainerHighest,
                colOnContainer: c.colOnSurface,
                colContainerHover: c.colSurfaceContainerHighestHover,
                colContainerActive: c.colSurfaceContainerHighestActive,
                colAccent: c.colSecondary,
                colOnAccent: c.colOnSecondary,
                colAccentHover: c.colSecondaryHover,
                colAccentActive: c.colSecondaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colOnSurfaceVariant
            },
            "neutralContainer": {
                colBackground: c.colSurfaceContainerHigh,
                colOnBackground: c.colOnSurface,
                colBackgroundHover: c.colSurfaceContainerHighestHover,
                colBackgroundActive: c.colSurfaceContainerHighestActive,
                colBackgroundVariant: c.colSurfaceContainerHighest,
                colOnBackgroundVariant: c.colOnSurface,
                colBackgroundVariantHover: c.colSurfaceContainerHighestHover,
                colBackgroundVariantActive: c.colSurfaceContainerHighestActive,
                colContainer: c.colSurfaceContainerHigh,
                colOnContainer: c.colOnSurface,
                colContainerHover: c.colSurfaceContainerHighestHover,
                colContainerActive: c.colSurfaceContainerHighestActive,
                colAccent: c.colSecondary,
                colOnAccent: c.colOnSecondary,
                colAccentHover: c.colSecondaryHover,
                colAccentActive: c.colSecondaryActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colOnSurfaceVariant
            },
            "alert": {
                colBackground: c.colErrorContainer,
                colOnBackground: c.colOnErrorContainer,
                colBackgroundHover: c.colErrorContainerHover,
                colBackgroundActive: c.colErrorContainerActive,
                colBackgroundVariant: c.colError,
                colOnBackgroundVariant: c.colOnError,
                colBackgroundVariantHover: c.colErrorHover,
                colBackgroundVariantActive: c.colErrorActive,
                colContainer: c.colErrorContainer,
                colOnContainer: c.colOnErrorContainer,
                colContainerHover: c.colErrorContainerHover,
                colContainerActive: c.colErrorContainerActive,
                colAccent: c.colError,
                colOnAccent: c.colOnError,
                colAccentHover: c.colErrorHover,
                colAccentActive: c.colErrorActive,
                colBare: c.colOnLayer1,
                colBareAccent: c.colError
            }
        };
    }

    function resolve(colorMode) {
        return palettes[normalizeMode(colorMode)] || palettes["primary"];
    }
}
