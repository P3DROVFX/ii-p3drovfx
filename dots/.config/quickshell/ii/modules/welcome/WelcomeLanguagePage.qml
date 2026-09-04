import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property bool nextButtonHovered: false

    readonly property var languageNames: ({
        "de_DE": "Deutsch",
        "en_US": "English (United States)",
        "es_MX": "Español (México)",
        "fr_FR": "Français",
        "he_HE": "עברית",
        "id_ID": "Bahasa Indonesia",
        "it_IT": "Italiano",
        "ja_JP": "日本語",
        "pt_BR": "Português (Brasil)",
        "ru_RU": "Русский",
        "tr_TR": "Türkçe",
        "uk_UA": "Українська",
        "vi_VN": "Tiếng Việt",
        "zh_CN": "简体中文"
    })

    /**
     * The same languages named in the language currently on screen. Someone
     * looking for their own language reads the native name; someone who
     * landed here by accident, in a script they cannot read, needs the second
     * line to find their way back out.
     */
    readonly property var languageEndonyms: ({
        "de_DE": Translation.tr("German"),
        "en_US": Translation.tr("English (United States)"),
        "es_MX": Translation.tr("Spanish (Mexico)"),
        "fr_FR": Translation.tr("French"),
        "he_HE": Translation.tr("Hebrew"),
        "id_ID": Translation.tr("Indonesian"),
        "it_IT": Translation.tr("Italian"),
        "ja_JP": Translation.tr("Japanese"),
        "pt_BR": Translation.tr("Portuguese (Brazil)"),
        "ru_RU": Translation.tr("Russian"),
        "tr_TR": Translation.tr("Turkish"),
        "uk_UA": Translation.tr("Ukrainian"),
        "vi_VN": Translation.tr("Vietnamese"),
        "zh_CN": Translation.tr("Chinese (Simplified)")
    })

    readonly property var languageOptions: {
        const codes = Translation.allAvailableLanguages && Translation.allAvailableLanguages.length > 0
            ? Array.from(Translation.allAvailableLanguages)
            : ["en_US"];
        if (!codes.includes("en_US"))
            codes.unshift("en_US");
        codes.sort((a, b) => a === "en_US" ? -1 : b === "en_US" ? 1 : a.localeCompare(b));
        return codes.map(code => {
            const label = root.languageNames[code] || code;
            const endonym = root.languageEndonyms[code] || "";
            return {
                value: code,
                label: label,
                // A language whose two names are the same needs only one line.
                secondaryLabel: endonym === label ? "" : endonym
            };
        });
    }

    readonly property string configuredLanguage: Config.options.language.ui
    property string selectedLanguage: root.languageOptions.some(option => option.value === root.configuredLanguage)
        ? root.configuredLanguage
        : "en_US"

    function selectLanguage(code: string) {
        root.selectedLanguage = code;
        Config.options.language.ui = code;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        anchors.topMargin: Appearance.rounding.small
        spacing: Appearance.rounding.small

        WelcomeChoiceList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Appearance.rounding.large * 8
            choices: root.languageOptions
            currentValue: root.selectedLanguage
            onChosen: value => root.selectLanguage(value)
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: noticeText.implicitHeight + Appearance.rounding.normal * 2
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            StyledText {
                id: noticeText
                anchors.fill: parent
                anchors.margins: Appearance.rounding.normal
                text: Translation.tr("More languages can be translated with AI later from Language settings.")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
