.pragma library

// Siblings that share a registry icon take turns through its pool, in
// registry order, so a page of clocks is not one glyph thirty times.
const pools = {
    "schedule": ["schedule", "nest_clock_farsight_analog", "nest_clock_farsight_digital", "alarm", "avg_time",
        "more_time", "watch", "history_toggle_off", "update", "timelapse", "hourglass_top", "pace",
        "alarm_on", "watch_later", "browse_gallery", "shutter_speed"],
    "image": ["image", "photo_library", "landscape", "panorama", "photo_frame", "filter_hdr", "imagesmode", "photo"],
    "cloud": ["cloud", "partly_cloudy_day", "rainy", "thunderstorm", "weather_snowy", "foggy", "air"],
    "sunny": ["sunny", "clear_day", "wb_twilight", "routine", "light_mode"],
    "calendar_month": ["calendar_month", "date_range", "today", "event_note"],
    "play_circle": ["play_circle", "music_note", "queue_music", "library_music"],
    "graphic_eq": ["graphic_eq", "equalizer", "waves", "speaker"]
};

function glyphFor(widget, allWidgets) {
    const icon = widget?.icon ?? "widgets";
    const pool = pools[icon];
    if (!pool)
        return icon;
    let turn = 0;
    for (const other of allWidgets ?? []) {
        if (other === widget || other?.widgetId === widget?.widgetId)
            break;
        if (other?.icon === icon)
            turn++;
    }
    return pool[turn % pool.length];
}
