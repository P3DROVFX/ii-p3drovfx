pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string currentScheme: Config.options.background.widgets.colorScheme ?? "default"

    // Material 3 Color Schemes for Background Widgets
    // Usando propriedades de getter ou ligadas diretamente às propriedades do Appearance.colors
    readonly property var schemes: ({
        "default": {
            "name": Translation.tr("Default Surface"),
            "cardBgColor": Appearance.colors.colSurfaceContainerHigh,
            "textColorOnBg": Appearance.colors.colOnSurfaceVariant,
            "accentColor": Appearance.colors.colPrimary,
            "onAccentColor": Appearance.colors.colOnPrimary,
            "pillBgColor": Appearance.colors.colSurfaceContainerHighest,
            "pillFillColor": Appearance.colors.colSecondaryContainer,
            "textColorOnPillFill": Appearance.colors.colOnSecondaryContainer,
            "textColorOnPillTrack": Appearance.colors.colOnSurface,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnSurfaceVariant.r, Appearance.colors.colOnSurfaceVariant.g, Appearance.colors.colOnSurfaceVariant.b, 0.6),
            "innerShapeColor": Appearance.colors.colSurfaceContainerHighest,
            "highlightCircleColor": Appearance.colors.colOnSurfaceVariant,
            "highlightTextColor": Appearance.colors.colSurfaceContainerHigh
        },
        "expressive_primary": {
            "name": Translation.tr("Expressive Primary"),
            "cardBgColor": Appearance.colors.colPrimaryContainer,
            "textColorOnBg": Appearance.colors.colOnPrimaryContainer,
            "accentColor": Appearance.colors.colPrimary,
            "onAccentColor": Appearance.colors.colOnPrimary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.25),
            "pillFillColor": Appearance.colors.colPrimary,
            "textColorOnPillFill": Appearance.colors.colOnPrimary,
            "textColorOnPillTrack": Appearance.colors.colOnPrimaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnPrimaryContainer.r, Appearance.colors.colOnPrimaryContainer.g, Appearance.colors.colOnPrimaryContainer.b, 0.7),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.35),
            "highlightCircleColor": Appearance.colors.colPrimary,
            "highlightTextColor": Appearance.colors.colOnPrimary
        },
        "expressive_secondary": {
            "name": Translation.tr("Expressive Secondary"),
            "cardBgColor": Appearance.colors.colSecondaryContainer,
            "textColorOnBg": Appearance.colors.colOnSecondaryContainer,
            "accentColor": Appearance.colors.colSecondary,
            "onAccentColor": Appearance.colors.colOnSecondary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.25),
            "pillFillColor": Appearance.colors.colSecondary,
            "textColorOnPillFill": Appearance.colors.colOnSecondary,
            "textColorOnPillTrack": Appearance.colors.colOnSecondaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnSecondaryContainer.r, Appearance.colors.colOnSecondaryContainer.g, Appearance.colors.colOnSecondaryContainer.b, 0.7),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.35),
            "highlightCircleColor": Appearance.colors.colSecondary,
            "highlightTextColor": Appearance.colors.colOnSecondary
        },
        "expressive_tertiary": {
            "name": Translation.tr("Expressive Tertiary"),
            "cardBgColor": Appearance.colors.colTertiaryContainer,
            "textColorOnBg": Appearance.colors.colOnTertiaryContainer,
            "accentColor": Appearance.colors.colTertiary,
            "onAccentColor": Appearance.colors.colOnTertiary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.25),
            "pillFillColor": Appearance.colors.colTertiary,
            "textColorOnPillFill": Appearance.colors.colOnTertiary,
            "textColorOnPillTrack": Appearance.colors.colOnTertiaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnTertiaryContainer.r, Appearance.colors.colOnTertiaryContainer.g, Appearance.colors.colOnTertiaryContainer.b, 0.7),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.35),
            "highlightCircleColor": Appearance.colors.colTertiary,
            "highlightTextColor": Appearance.colors.colOnTertiary
        },
        "hero_primary": {
            "name": Translation.tr("Hero Primary"),
            "cardBgColor": Appearance.colors.colPrimary,
            "textColorOnBg": Appearance.colors.colOnPrimary,
            "accentColor": Appearance.colors.colPrimaryContainer,
            "onAccentColor": Appearance.colors.colOnPrimaryContainer,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.2),
            "pillFillColor": Appearance.colors.colPrimaryContainer,
            "textColorOnPillFill": Appearance.colors.colOnPrimaryContainer,
            "textColorOnPillTrack": Appearance.colors.colOnPrimary,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnPrimary.r, Appearance.colors.colOnPrimary.g, Appearance.colors.colOnPrimary.b, 0.75),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.25),
            "highlightCircleColor": Appearance.colors.colOnPrimary,
            "highlightTextColor": Appearance.colors.colPrimary
        },
        "vibrant_mix": {
            "name": Translation.tr("Vibrant Mix"),
            "cardBgColor": ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.4),
            "textColorOnBg": Appearance.colors.colOnPrimaryContainer,
            "accentColor": Appearance.colors.colTertiary,
            "onAccentColor": Appearance.colors.colOnTertiary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.3),
            "pillFillColor": Appearance.colors.colTertiary,
            "textColorOnPillFill": Appearance.colors.colOnTertiary,
            "textColorOnPillTrack": Appearance.colors.colOnPrimaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnPrimaryContainer.r, Appearance.colors.colOnPrimaryContainer.g, Appearance.colors.colOnPrimaryContainer.b, 0.7),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.6),
            "highlightCircleColor": Appearance.colors.colTertiary,
            "highlightTextColor": Appearance.colors.colOnTertiary
        },
        "muted_surface": {
            "name": Translation.tr("Muted Low Surface"),
            "cardBgColor": Appearance.colors.colSurfaceContainerLow,
            "textColorOnBg": Appearance.colors.colOnSurface,
            "accentColor": Appearance.colors.colSecondary,
            "onAccentColor": Appearance.colors.colOnSecondary,
            "pillBgColor": Appearance.colors.colSurfaceContainerHigh,
            "pillFillColor": Appearance.colors.colSecondaryContainer,
            "textColorOnPillFill": Appearance.colors.colOnSecondaryContainer,
            "textColorOnPillTrack": Appearance.colors.colOnSurface,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnSurface.r, Appearance.colors.colOnSurface.g, Appearance.colors.colOnSurface.b, 0.6),
            "innerShapeColor": Appearance.colors.colSurfaceContainer,
            "highlightCircleColor": Appearance.colors.colSecondary,
            "highlightTextColor": Appearance.colors.colOnSecondary
        }
    })

    // Funções auxiliares para calcular dinamicamente sem congelar no mapa inicial do JS
    function getCardBgColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondaryContainer;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiaryContainer;
        if (scheme === "hero_primary") return Appearance.colors.colPrimary;
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.4);
        if (scheme === "muted_surface") return Appearance.colors.colSurfaceContainerLow;
        return Appearance.colors.colSurfaceContainerHigh;
    }

    function getTextColorOnBg(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondaryContainer;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiaryContainer;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "muted_surface") return Appearance.colors.colOnSurface;
        return Appearance.colors.colOnSurfaceVariant;
    }

    function getAccentColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondary;
        return Appearance.colors.colPrimary;
    }

    function getOnAccentColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colOnSecondary;
        return Appearance.colors.colOnPrimary;
    }

    function getPillBgColor(scheme) {
        if (scheme === "expressive_primary") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.25);
        if (scheme === "expressive_secondary") return ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.25);
        if (scheme === "expressive_tertiary") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.25);
        if (scheme === "hero_primary") return ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.2);
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.3);
        if (scheme === "muted_surface") return Appearance.colors.colSurfaceContainerHigh;
        return Appearance.colors.colSurfaceContainerHighest;
    }

    function getPillFillColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondaryContainer;
        return Appearance.colors.colSecondaryContainer;
    }

    function getSubtextColorOnBg(scheme) {
        let textCol = getTextColorOnBg(scheme);
        return Qt.rgba(textCol.r, textCol.g, textCol.b, 0.7);
    }

    function getInnerShapeColor(scheme) {
        if (scheme === "expressive_primary") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.35);
        if (scheme === "expressive_secondary") return ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.35);
        if (scheme === "expressive_tertiary") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.35);
        if (scheme === "hero_primary") return ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.25);
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.6);
        if (scheme === "muted_surface") return Appearance.colors.colSurfaceContainer;
        return Appearance.colors.colSurfaceContainerHighest;
    }

    function getHighlightCircleColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondary;
        return Appearance.colors.colOnSurfaceVariant;
    }

    function getHighlightTextColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colOnSecondary;
        return Appearance.colors.colSurfaceContainerHigh;
    }

    // Dynamic reactive color properties
    readonly property color cardBgColor: getCardBgColor(currentScheme)
    readonly property color textColorOnBg: getTextColorOnBg(currentScheme)
    readonly property color accentColor: getAccentColor(currentScheme)
    readonly property color onAccentColor: getOnAccentColor(currentScheme)
    readonly property color pillBgColor: getPillBgColor(currentScheme)
    readonly property color pillFillColor: getPillFillColor(currentScheme)
    readonly property color textColorOnPillFill: getOnAccentColor(currentScheme)
    readonly property color textColorOnPillTrack: textColorOnBg
    readonly property color subtextColorOnBg: getSubtextColorOnBg(currentScheme)
    readonly property color innerShapeColor: getInnerShapeColor(currentScheme)
    readonly property color highlightCircleColor: getHighlightCircleColor(currentScheme)
    readonly property color highlightTextColor: getHighlightTextColor(currentScheme)

    // Key list for iteration in settings
    readonly property list<string> availableSchemes: [
        "default",
        "expressive_primary",
        "expressive_secondary",
        "expressive_tertiary",
        "hero_primary",
        "vibrant_mix",
        "muted_surface"
    ]
}
