pragma ComponentBehavior: Bound

import Qt.labs.qmlmodels
import qs.modules.akebono.desktop.widgets.calendar
import qs.modules.akebono.desktop.widgets.image
import qs.modules.akebono.desktop.widgets.media
import qs.modules.akebono.desktop.widgets.notes
import qs.modules.akebono.desktop.widgets.weather

DelegateChooser {
    role: "type"

    DelegateChoice {
        roleValue: "calendar"
        CalendarWidget {
            required property var modelData
            widgetData: modelData
        }
    }
    DelegateChoice {
        roleValue: "media"
        MediaWidget {
            required property var modelData
            widgetData: modelData
        }
    }
    DelegateChoice {
        roleValue: "weather"
        WeatherWidget {
            required property var modelData
            widgetData: modelData
        }
    }

    DelegateChoice {
        roleValue: "image"
        ImageWidget {
            required property var modelData
            widgetData: modelData
        }
    }
    DelegateChoice {
        roleValue: "notes"
        NotesWidget {
            required property var modelData
            widgetData: modelData
        }
    }
}
