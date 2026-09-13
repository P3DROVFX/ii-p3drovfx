pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string currentScheme: Config.options.background.widgets.colorScheme ?? "default"

    readonly property real backgroundTintOpacity: {
        if (!(Config.options.background.widgets.tintOpacityEnabled ?? false))
            return 1;
        const value = Config.options.background.widgets.tintOpacity ?? 0.55;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.55;
    }

    // Apply at the background paint site, after selecting the palette/album
    // color. Keep raw palette tokens opaque: clocks also use them for hands,
    // digits and masks. Multiplication preserves any existing surface alpha.
    function tintBackground(background: color): color {
        if (root.backgroundTintOpacity === 1)
            return background;
        return Qt.rgba(background.r, background.g, background.b,
            background.a * root.backgroundTintOpacity);
    }

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
            "highlightTextColor": Appearance.colors.colSurfaceContainerHigh,
            "successColor": Appearance.m3colors.m3success,
            "warningColor": Appearance.colors.colError,
            "outlineColor": Appearance.colors.colOutline,
            "surfaceVariantColor": Appearance.m3colors.m3surfaceVariant
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
            "highlightTextColor": Appearance.colors.colOnPrimary,
            "successColor": Appearance.colors.colTertiary,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.3),
            "outlineColor": Appearance.colors.colPrimaryContainer,
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5)
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
            "highlightTextColor": Appearance.colors.colOnSecondary,
            "successColor": Appearance.colors.colPrimary,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.3),
            "outlineColor": Appearance.colors.colSecondaryContainer,
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5)
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
            "highlightTextColor": Appearance.colors.colOnTertiary,
            "successColor": Appearance.m3colors.m3successContainer,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.3),
            "outlineColor": Appearance.colors.colTertiaryContainer,
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colTertiaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5)
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
            "highlightTextColor": Appearance.colors.colPrimary,
            "successColor": Appearance.colors.colSecondaryContainer,
            "warningColor": Appearance.colors.colErrorContainer,
            "outlineColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.4),
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.2)
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
            "highlightTextColor": Appearance.colors.colOnTertiary,
            "successColor": Appearance.colors.colPrimary,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.4),
            "outlineColor": ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.5),
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.2)
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
            "highlightTextColor": Appearance.colors.colOnSecondary,
            "successColor": Appearance.colors.colTertiary,
            "warningColor": Appearance.colors.colError,
            "outlineColor": Appearance.colors.colOutline,
            "surfaceVariantColor": Appearance.m3colors.m3surfaceVariant
        },
        "secondary_fixed": {
            "name": Translation.tr("Secondary Fixed"),
            "cardBgColor": Appearance.m3colors.m3secondaryFixed,
            "textColorOnBg": Appearance.m3colors.m3onSecondaryFixed,
            "accentColor": Appearance.colors.colSecondary,
            "onAccentColor": Appearance.colors.colOnSecondary,
            "pillBgColor": ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.colors.colSecondary, 0.25),
            "pillFillColor": Appearance.colors.colSecondaryContainer,
            "textColorOnPillFill": Appearance.colors.colOnSecondaryContainer,
            "textColorOnPillTrack": Appearance.m3colors.m3onSecondaryFixed,
            "subtextColorOnBg": Qt.rgba(Appearance.m3colors.m3onSecondaryFixed.r, Appearance.m3colors.m3onSecondaryFixed.g, Appearance.m3colors.m3onSecondaryFixed.b, 0.65),
            "innerShapeColor": ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.colors.colSecondary, 0.3),
            "highlightCircleColor": Appearance.colors.colSecondary,
            "highlightTextColor": Appearance.m3colors.m3onSecondaryFixed,
            "successColor": Appearance.m3colors.m3success,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.2),
            "outlineColor": Appearance.m3colors.m3onSecondaryFixedVariant,
            "surfaceVariantColor": ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.m3colors.m3onSecondaryFixed, 0.15)
        },
        "tertiary_showcase": {
            "name": Translation.tr("Tertiary Showcase"),
            "cardBgColor": Appearance.colors.colTertiaryContainer,
            "textColorOnBg": Appearance.colors.colOnTertiaryContainer,
            "accentColor": Appearance.colors.colTertiary,
            "onAccentColor": Appearance.colors.colOnTertiary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.2),
            "pillFillColor": Appearance.colors.colPrimary,
            "textColorOnPillFill": Appearance.colors.colOnPrimary,
            "textColorOnPillTrack": Appearance.colors.colOnTertiaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnTertiaryContainer.r, Appearance.colors.colOnTertiaryContainer.g, Appearance.colors.colOnTertiaryContainer.b, 0.65),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.3),
            "highlightCircleColor": Appearance.colors.colPrimary,
            "highlightTextColor": Appearance.colors.colOnPrimary,
            "successColor": Appearance.colors.colSecondary,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.25),
            "outlineColor": ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.4),
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.2)
        },
        "error_alert": {
            "name": Translation.tr("Error Alert"),
            "cardBgColor": Appearance.colors.colErrorContainer,
            "textColorOnBg": Appearance.colors.colOnErrorContainer,
            "accentColor": Appearance.colors.colError,
            "onAccentColor": Appearance.colors.colOnError,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.25),
            "pillFillColor": Appearance.colors.colError,
            "textColorOnPillFill": Appearance.colors.colOnError,
            "textColorOnPillTrack": Appearance.colors.colOnErrorContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnErrorContainer.r, Appearance.colors.colOnErrorContainer.g, Appearance.colors.colOnErrorContainer.b, 0.65),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.35),
            "highlightCircleColor": Appearance.colors.colError,
            "highlightTextColor": Appearance.colors.colOnError,
            "successColor": Appearance.m3colors.m3success,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.m3colors.m3onErrorContainer, 0.5),
            "outlineColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.5),
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.2)
        },
        "inverse_surface": {
            "name": Translation.tr("Inverse Surface"),
            "cardBgColor": Appearance.m3colors.m3inverseSurface,
            "textColorOnBg": Appearance.m3colors.m3inverseOnSurface,
            "accentColor": Appearance.m3colors.m3inversePrimary,
            "onAccentColor": Appearance.m3colors.m3inverseOnSurface,
            "pillBgColor": ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inversePrimary, 0.3),
            "pillFillColor": Appearance.m3colors.m3inversePrimary,
            "textColorOnPillFill": Appearance.m3colors.m3inverseOnSurface,
            "textColorOnPillTrack": Appearance.m3colors.m3inverseOnSurface,
            "subtextColorOnBg": Qt.rgba(Appearance.m3colors.m3inverseOnSurface.r, Appearance.m3colors.m3inverseOnSurface.g, Appearance.m3colors.m3inverseOnSurface.b, 0.6),
            "innerShapeColor": ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inverseOnSurface, 0.2),
            "highlightCircleColor": Appearance.m3colors.m3inversePrimary,
            "highlightTextColor": Appearance.m3colors.m3inverseOnSurface,
            "successColor": ColorUtils.mix(Appearance.m3colors.m3success, Appearance.m3colors.m3inverseSurface, 0.3),
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.m3colors.m3inversePrimary, 0.3),
            "outlineColor": ColorUtils.mix(Appearance.m3colors.m3inverseOnSurface, Appearance.m3colors.m3inverseSurface, 0.4),
            "surfaceVariantColor": ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inverseOnSurface, 0.15)
        },
        "tri_blend": {
            "name": Translation.tr("Tri-Color Blend"),
            "cardBgColor": Appearance.colors.colSurfaceContainerHigh,
            "textColorOnBg": Appearance.colors.colOnPrimaryContainer,
            "accentColor": Appearance.colors.colSecondary,
            "onAccentColor": Appearance.colors.colOnSecondary,
            "pillBgColor": ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colTertiaryContainer, 0.35),
            "pillFillColor": Appearance.colors.colTertiary,
            "textColorOnPillFill": Appearance.colors.colOnTertiary,
            "textColorOnPillTrack": Appearance.colors.colOnPrimaryContainer,
            "subtextColorOnBg": Qt.rgba(Appearance.colors.colOnPrimaryContainer.r, Appearance.colors.colOnPrimaryContainer.g, Appearance.colors.colOnPrimaryContainer.b, 0.6),
            "innerShapeColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.25),
            "highlightCircleColor": Appearance.colors.colTertiary,
            "highlightTextColor": Appearance.colors.colOnTertiary,
            "successColor": Appearance.colors.colPrimary,
            "warningColor": ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.4),
            "outlineColor": ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colSecondary, 0.5),
            "surfaceVariantColor": ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.3)
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
        if (scheme === "secondary_fixed") return Appearance.m3colors.m3secondaryFixed;
        if (scheme === "tertiary_showcase") return Appearance.colors.colTertiaryContainer;
        if (scheme === "error_alert") return Appearance.colors.colErrorContainer;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inverseSurface;
        if (scheme === "tri_blend") return Appearance.colors.colSurfaceContainerHigh;
        return Appearance.colors.colSurfaceContainerHigh;
    }

    function getTextColorOnBg(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondaryContainer;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiaryContainer;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "muted_surface") return Appearance.colors.colOnSurface;
        if (scheme === "secondary_fixed") return Appearance.m3colors.m3onSecondaryFixed;
        if (scheme === "tertiary_showcase") return Appearance.colors.colOnTertiaryContainer;
        if (scheme === "error_alert") return Appearance.colors.colOnErrorContainer;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inverseOnSurface;
        if (scheme === "tri_blend") return Appearance.colors.colOnPrimaryContainer;
        return Appearance.colors.colOnSurfaceVariant;
    }

    function getAccentColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondary;
        if (scheme === "secondary_fixed") return Appearance.colors.colSecondary;
        if (scheme === "tertiary_showcase") return Appearance.colors.colTertiary;
        if (scheme === "error_alert") return Appearance.colors.colError;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inversePrimary;
        if (scheme === "tri_blend") return Appearance.colors.colSecondary;
        return Appearance.colors.colPrimary;
    }

    function getOnAccentColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colOnSecondary;
        if (scheme === "secondary_fixed") return Appearance.colors.colOnSecondary;
        if (scheme === "tertiary_showcase") return Appearance.colors.colOnTertiary;
        if (scheme === "error_alert") return Appearance.colors.colOnError;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inverseOnSurface;
        if (scheme === "tri_blend") return Appearance.colors.colOnSecondary;
        return Appearance.colors.colOnPrimary;
    }

    function getPillBgColor(scheme) {
        if (scheme === "expressive_primary") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.25);
        if (scheme === "expressive_secondary") return ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colSecondaryContainer, 0.25);
        if (scheme === "expressive_tertiary") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.25);
        if (scheme === "hero_primary") return ColorUtils.mix(Appearance.colors.colOnPrimary, Appearance.colors.colPrimary, 0.2);
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.3);
        if (scheme === "muted_surface") return Appearance.colors.colSurfaceContainerHigh;
        if (scheme === "secondary_fixed") return ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.colors.colSecondary, 0.25);
        if (scheme === "tertiary_showcase") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.2);
        if (scheme === "error_alert") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.25);
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inversePrimary, 0.3);
        if (scheme === "tri_blend") return ColorUtils.mix(Appearance.colors.colSecondary, Appearance.colors.colTertiaryContainer, 0.35);
        return Appearance.colors.colSurfaceContainerHighest;
    }

    function getPillFillColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondaryContainer;
        if (scheme === "secondary_fixed") return Appearance.colors.colSecondaryContainer;
        if (scheme === "tertiary_showcase") return Appearance.colors.colPrimary;
        if (scheme === "error_alert") return Appearance.colors.colError;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inversePrimary;
        if (scheme === "tri_blend") return Appearance.colors.colTertiary;
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
        if (scheme === "secondary_fixed") return ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.colors.colSecondary, 0.3);
        if (scheme === "tertiary_showcase") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.3);
        if (scheme === "error_alert") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.35);
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inverseOnSurface, 0.2);
        if (scheme === "tri_blend") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.25);
        return Appearance.colors.colSurfaceContainerHighest;
    }

    function getHighlightCircleColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colSecondary;
        if (scheme === "secondary_fixed") return Appearance.colors.colSecondary;
        if (scheme === "tertiary_showcase") return Appearance.colors.colPrimary;
        if (scheme === "error_alert") return Appearance.colors.colError;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inversePrimary;
        if (scheme === "tri_blend") return Appearance.colors.colTertiary;
        return Appearance.colors.colOnSurfaceVariant;
    }

    function getHighlightTextColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colOnPrimary;
        if (scheme === "expressive_secondary") return Appearance.colors.colOnSecondary;
        if (scheme === "expressive_tertiary") return Appearance.colors.colOnTertiary;
        if (scheme === "hero_primary") return Appearance.colors.colPrimary;
        if (scheme === "vibrant_mix") return Appearance.colors.colOnTertiary;
        if (scheme === "muted_surface") return Appearance.colors.colOnSecondary;
        if (scheme === "secondary_fixed") return Appearance.m3colors.m3onSecondaryFixed;
        if (scheme === "tertiary_showcase") return Appearance.colors.colOnPrimary;
        if (scheme === "error_alert") return Appearance.colors.colOnError;
        if (scheme === "inverse_surface") return Appearance.m3colors.m3inverseOnSurface;
        if (scheme === "tri_blend") return Appearance.colors.colOnTertiary;
        return Appearance.colors.colSurfaceContainerHigh;
    }

    function getSuccessColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colTertiary;
        if (scheme === "expressive_secondary") return Appearance.colors.colPrimary;
        if (scheme === "expressive_tertiary") return Appearance.m3colors.m3successContainer;
        if (scheme === "hero_primary") return Appearance.colors.colSecondaryContainer;
        if (scheme === "vibrant_mix") return Appearance.colors.colPrimary;
        if (scheme === "muted_surface") return Appearance.colors.colTertiary;
        if (scheme === "secondary_fixed") return Appearance.m3colors.m3success;
        if (scheme === "tertiary_showcase") return Appearance.colors.colSecondary;
        if (scheme === "error_alert") return Appearance.m3colors.m3success;
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.m3colors.m3success, Appearance.m3colors.m3inverseSurface, 0.3);
        if (scheme === "tri_blend") return Appearance.colors.colPrimary;
        return Appearance.m3colors.m3success;
    }

    function getWarningColor(scheme) {
        if (scheme === "expressive_primary") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.3);
        if (scheme === "expressive_secondary") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.3);
        if (scheme === "expressive_tertiary") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.3);
        if (scheme === "hero_primary") return Appearance.colors.colErrorContainer;
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colTertiary, 0.4);
        if (scheme === "muted_surface") return Appearance.colors.colError;
        if (scheme === "secondary_fixed") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.2);
        if (scheme === "tertiary_showcase") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.25);
        if (scheme === "error_alert") return ColorUtils.mix(Appearance.colors.colError, Appearance.m3colors.m3onErrorContainer, 0.5);
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.colors.colError, Appearance.m3colors.m3inversePrimary, 0.3);
        if (scheme === "tri_blend") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colSecondary, 0.4);
        return Appearance.colors.colError;
    }

    function getOutlineColor(scheme) {
        if (scheme === "expressive_primary") return Appearance.colors.colPrimaryContainer;
        if (scheme === "expressive_secondary") return Appearance.colors.colSecondaryContainer;
        if (scheme === "expressive_tertiary") return Appearance.colors.colTertiaryContainer;
        if (scheme === "hero_primary") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.4);
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.5);
        if (scheme === "muted_surface") return Appearance.colors.colOutline;
        if (scheme === "secondary_fixed") return Appearance.m3colors.m3onSecondaryFixedVariant;
        if (scheme === "tertiary_showcase") return ColorUtils.mix(Appearance.colors.colTertiary, Appearance.colors.colTertiaryContainer, 0.4);
        if (scheme === "error_alert") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.5);
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.m3colors.m3inverseOnSurface, Appearance.m3colors.m3inverseSurface, 0.4);
        if (scheme === "tri_blend") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colSecondary, 0.5);
        return Appearance.colors.colOutline;
    }

    function getSurfaceVariantColor(scheme) {
        if (scheme === "expressive_primary") return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5);
        if (scheme === "expressive_secondary") return ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5);
        if (scheme === "expressive_tertiary") return ColorUtils.mix(Appearance.colors.colTertiaryContainer, Appearance.colors.colSurfaceContainerHigh, 0.5);
        if (scheme === "hero_primary") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnPrimary, 0.2);
        if (scheme === "vibrant_mix") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.2);
        if (scheme === "muted_surface") return Appearance.m3colors.m3surfaceVariant;
        if (scheme === "secondary_fixed") return ColorUtils.mix(Appearance.m3colors.m3secondaryFixed, Appearance.m3colors.m3onSecondaryFixed, 0.15);
        if (scheme === "tertiary_showcase") return ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colTertiaryContainer, 0.2);
        if (scheme === "error_alert") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colErrorContainer, 0.2);
        if (scheme === "inverse_surface") return ColorUtils.mix(Appearance.m3colors.m3inverseSurface, Appearance.m3colors.m3inverseOnSurface, 0.15);
        if (scheme === "tri_blend") return ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, 0.3);
        return Appearance.m3colors.m3surfaceVariant;
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
    readonly property color successColor: getSuccessColor(currentScheme)
    readonly property color warningColor: getWarningColor(currentScheme)
    readonly property color outlineColor: getOutlineColor(currentScheme)
    readonly property color surfaceVariantColor: getSurfaceVariantColor(currentScheme)

    // Key list for iteration in settings
    readonly property list<string> availableSchemes: [
        "default",
        "expressive_primary",
        "expressive_secondary",
        "expressive_tertiary",
        "hero_primary",
        "vibrant_mix",
        "muted_surface",
        "secondary_fixed",
        "tertiary_showcase",
        "error_alert",
        "inverse_surface",
        "tri_blend"
    ]
}
