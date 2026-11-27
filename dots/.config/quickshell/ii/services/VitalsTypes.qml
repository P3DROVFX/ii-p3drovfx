pragma Singleton

import QtQuick
import Quickshell

/**
 * What each ii Vitals key is (scripts/iiLink/PROTOCOL.md, "Vitals" → type keys): its name,
 * kind, unit, Material Symbols icon, app page, and how a value reads. Shared by the app,
 * the widget, the sidebar tile and the assistant. A key this does not know still shows,
 * on the More page, by the kind its Day gives it.
 */
Singleton {
    id: root

    /// The app's destinations, in rail order.
    readonly property var pages: ["today", "activity", "sleep", "heart", "workouts", "body", "more"]

    // `fmt` picks a formatter below; sessions' values are minutes.
    readonly property var types: ({
        steps: { label: Translation.tr("Steps"), kind: "totals", unit: Translation.tr("steps"), icon: "directions_walk", page: "activity", fmt: "count" },
        distanceM: { label: Translation.tr("Distance"), kind: "totals", unit: "km", icon: "straighten", page: "activity", fmt: "distance" },
        floors: { label: Translation.tr("Floors"), kind: "totals", unit: Translation.tr("floors"), icon: "stairs", page: "activity", fmt: "count" },
        elevationM: { label: Translation.tr("Elevation gained"), kind: "totals", unit: "m", icon: "landscape", page: "activity", fmt: "meters" },
        activeKcal: { label: Translation.tr("Active calories"), kind: "totals", unit: "kcal", icon: "local_fire_department", page: "activity", fmt: "kcal" },
        totalKcal: { label: Translation.tr("Total calories"), kind: "totals", unit: "kcal", icon: "mode_heat", page: "activity", fmt: "kcal" },
        activeMin: { label: Translation.tr("Active time"), kind: "totals", unit: "min", icon: "timer", page: "activity", fmt: "duration" },
        wheelchairPushes: { label: Translation.tr("Wheelchair pushes"), kind: "totals", unit: Translation.tr("pushes"), icon: "accessible", page: "activity", fmt: "count" },
        energy: { label: Translation.tr("Energy score"), kind: "scores", unit: "", icon: "bolt", page: "activity", fmt: "score" },
        sleep: { label: Translation.tr("Sleep"), kind: "sessions", unit: "min", icon: "bedtime", page: "sleep", fmt: "duration" },
        heartRate: { label: Translation.tr("Heart rate"), kind: "samples", unit: "bpm", icon: "favorite", page: "heart", fmt: "bpm" },
        restingHeartRate: { label: Translation.tr("Resting heart rate"), kind: "samples", unit: "bpm", icon: "monitor_heart", page: "heart", fmt: "bpm" },
        hrvRmssdMs: { label: Translation.tr("Heart rate variability"), kind: "samples", unit: "ms", icon: "ecg_heart", page: "heart", fmt: "ms" },
        spo2Pct: { label: Translation.tr("Blood oxygen"), kind: "samples", unit: "%", icon: "spo2", page: "heart", fmt: "pct" },
        respiratoryRate: { label: Translation.tr("Respiratory rate"), kind: "samples", unit: "/min", icon: "pulmonology", page: "heart", fmt: "perMin" },
        bloodPressure: { label: Translation.tr("Blood pressure"), kind: "measurements", unit: "mmHg", icon: "blood_pressure", page: "heart", primary: "systolic" },
        vo2Max: { label: Translation.tr("VO₂ max"), kind: "measurements", unit: "ml/kg/min", icon: "sprint", page: "heart", primary: "mlKgMin" },
        exercise: { label: Translation.tr("Workouts"), kind: "sessions", unit: "min", icon: "exercise", page: "workouts", fmt: "duration" },
        speedMps: { label: Translation.tr("Speed"), kind: "samples", unit: "km/h", icon: "speed", page: "workouts", fmt: "speed" },
        powerW: { label: Translation.tr("Power"), kind: "samples", unit: "W", icon: "electric_bolt", page: "workouts", fmt: "watts" },
        stepsCadence: { label: Translation.tr("Cadence"), kind: "samples", unit: Translation.tr("steps/min"), icon: "footprint", page: "workouts", fmt: "spm" },
        cyclingCadenceRpm: { label: Translation.tr("Pedalling cadence"), kind: "samples", unit: "rpm", icon: "directions_bike", page: "workouts", fmt: "rpm" },
        skinTempC: { label: Translation.tr("Skin temperature"), kind: "samples", unit: "°C", icon: "thermostat", page: "body", fmt: "celsius" },
        skinTempDeltaC: { label: Translation.tr("Skin temperature change"), kind: "samples", unit: "°C", icon: "thermostat", page: "body", fmt: "celsiusDelta" },
        body: { label: Translation.tr("Body composition"), kind: "measurements", unit: "kg", icon: "monitor_weight", page: "body", primary: "weightKg" },
        height: { label: Translation.tr("Height"), kind: "measurements", unit: "m", icon: "height", page: "body", primary: "m" },
        bodyTemp: { label: Translation.tr("Body temperature"), kind: "measurements", unit: "°C", icon: "device_thermostat", page: "body", primary: "c" },
        basalBodyTemp: { label: Translation.tr("Basal body temperature"), kind: "measurements", unit: "°C", icon: "thermometer", page: "body", primary: "c" },
        hydrationMl: { label: Translation.tr("Water"), kind: "totals", unit: "ml", icon: "water_drop", page: "more", fmt: "ml" },
        intakeKcal: { label: Translation.tr("Calories eaten"), kind: "totals", unit: "kcal", icon: "restaurant", page: "more", fmt: "kcal" },
        intakeProteinG: { label: Translation.tr("Protein"), kind: "totals", unit: "g", icon: "egg", page: "more", fmt: "grams" },
        intakeFatG: { label: Translation.tr("Fat"), kind: "totals", unit: "g", icon: "nutrition", page: "more", fmt: "grams" },
        intakeCarbsG: { label: Translation.tr("Carbohydrates"), kind: "totals", unit: "g", icon: "grain", page: "more", fmt: "grams" },
        intakeSugarG: { label: Translation.tr("Sugar"), kind: "totals", unit: "g", icon: "cookie", page: "more", fmt: "grams" },
        intakeFiberG: { label: Translation.tr("Fibre"), kind: "totals", unit: "g", icon: "nutrition", page: "more", fmt: "grams" },
        intakeSodiumMg: { label: Translation.tr("Sodium"), kind: "totals", unit: "mg", icon: "grain", page: "more", fmt: "milligrams" },
        intakeCaffeineMg: { label: Translation.tr("Caffeine"), kind: "totals", unit: "mg", icon: "coffee", page: "more", fmt: "milligrams" },
        mindfulness: { label: Translation.tr("Mindfulness"), kind: "sessions", unit: "min", icon: "self_improvement", page: "more", fmt: "duration" },
        menstruationPeriod: { label: Translation.tr("Period"), kind: "sessions", unit: "min", icon: "menstrual_health", page: "more", fmt: "duration" },
        bloodGlucose: { label: Translation.tr("Blood glucose"), kind: "measurements", unit: "mmol/L", icon: "glucose", page: "more", primary: "mmolL" },
        menstruationFlow: { label: Translation.tr("Menstrual flow"), kind: "measurements", unit: "", icon: "menstrual_health", page: "more" },
        ovulationTest: { label: Translation.tr("Ovulation test"), kind: "measurements", unit: "", icon: "egg", page: "more" },
        cervicalMucus: { label: Translation.tr("Cervical mucus"), kind: "measurements", unit: "", icon: "water_drop", page: "more" },
        intermenstrualBleeding: { label: Translation.tr("Spotting"), kind: "measurements", unit: "", icon: "bloodtype", page: "more" },
        sexualActivity: { label: Translation.tr("Sexual activity"), kind: "measurements", unit: "", icon: "favorite", page: "more" }
    })

    readonly property var _kindIcons: ({ totals: "functions", samples: "monitoring", sessions: "schedule", measurements: "straighten", scores: "star" })

    /// {label, kind, unit, icon, page, fmt?, primary?}; an unknown key gets its own name, the
    /// `kind` its Day files it under, a generic icon and the More page.
    function info(key: string, kind): var {
        return root.types[key] ?? { label: key, kind: kind ?? "", unit: "", icon: root._kindIcons[kind] ?? "monitoring", page: "more" };
    }

    function label(key: string): string { return root.info(key).label; }
    function icon(key: string, kind): string { return root.info(key, kind).icon; }
    function page(key: string): string { return root.info(key).page; }

    /// The pages with something to show for the `present` set (VitalsService.present).
    function pagesFor(present: var): var {
        const keys = Object.keys(present ?? {});
        if (keys.length === 0)
            return [];
        const have = { today: true };
        for (const k of keys)
            have[root.page(k)] = true;
        return root.pages.filter(p => have[p]);
    }

    /// The present keys a page shows, known ones in the registry's order, unknown after.
    function keysFor(pageName: string, present: var): var {
        const keys = Object.keys(present ?? {}).filter(k => root.page(k) === pageName);
        const order = Object.keys(root.types);
        return keys.sort((a, b) => {
            const ia = order.indexOf(a), ib = order.indexOf(b);
            if (ia < 0 || ib < 0)
                return ia < 0 && ib < 0 ? a.localeCompare(b) : (ia < 0 ? 1 : -1);
            return ia - ib;
        });
    }

    // ── Values ──────────────────────────────────────────────────────────

    function _n(v: real, decimals: int): string {
        return Number(v).toLocaleString(Qt.locale(), "f", decimals);
    }

    /// "1 h 48 min", "45 min".
    function duration(minutes: real): string {
        const m = Math.round(minutes);
        if (m < 60)
            return Translation.tr("%1 min").arg(m);
        return Translation.tr("%1 h %2 min").arg(Math.floor(m / 60)).arg(m % 60);
    }

    readonly property var _fmt: ({
        count: v => root._n(v, 0),
        score: v => root._n(v, 0),
        distance: v => v < 1000 ? Translation.tr("%1 m").arg(root._n(v, 0)) : Translation.tr("%1 km").arg(root._n(v / 1000, 1)),
        meters: v => Translation.tr("%1 m").arg(root._n(v, 0)),
        kcal: v => Translation.tr("%1 kcal").arg(root._n(v, 0)),
        duration: v => root.duration(v),
        bpm: v => Translation.tr("%1 bpm").arg(root._n(v, 0)),
        ms: v => Translation.tr("%1 ms").arg(root._n(v, 0)),
        pct: v => Translation.tr("%1 %").arg(root._n(v, 0)),
        perMin: v => Translation.tr("%1 /min").arg(root._n(v, 0)),
        celsius: v => Translation.tr("%1 °C").arg(root._n(v, 1)),
        celsiusDelta: v => Translation.tr("%1 °C").arg((v > 0 ? "+" : v < 0 ? "−" : "") + root._n(Math.abs(v), 1)),
        speed: v => Translation.tr("%1 km/h").arg(root._n(v * 3.6, 1)),
        watts: v => Translation.tr("%1 W").arg(root._n(v, 0)),
        spm: v => Translation.tr("%1 steps/min").arg(root._n(v, 0)),
        rpm: v => Translation.tr("%1 rpm").arg(root._n(v, 0)),
        ml: v => Translation.tr("%1 ml").arg(root._n(v, 0)),
        grams: v => Translation.tr("%1 g").arg(root._n(v, v < 10 ? 1 : 0)),
        milligrams: v => Translation.tr("%1 mg").arg(root._n(v, 0))
    })

    /**
     * A value of `key` as the app shows it: a number for totals, samples and scores, minutes
     * for sessions, the measurement entry for measurements (its main field reads; blood
     * pressure as systolic/diastolic). Unknown keys get the number as it is.
     */
    function format(key: string, value: var): string {
        if (value === null || value === undefined)
            return "–";
        const t = root.types[key];
        if (typeof value === "object") {
            if (key === "bloodPressure")
                return Translation.tr("%1/%2 mmHg").arg(root._n(value.systolic, 0)).arg(root._n(value.diastolic, 0));
            const field = t?.primary ?? Object.keys(value).find(f => f !== "time" && typeof value[f] === "number");
            return field ? root.formatField(field, value[field]) : "–";
        }
        if (typeof value !== "number" || !isFinite(value))
            return String(value);
        const f = root._fmt[t?.fmt ?? ""];
        return f ? f(value) : root._n(value, Number.isInteger(value) ? 0 : 1);
    }

    readonly property var fields: ({
        weightKg: { label: Translation.tr("Weight"), fmt: v => Translation.tr("%1 kg").arg(root._n(v, 1)) },
        bodyFatPct: { label: Translation.tr("Body fat"), fmt: v => Translation.tr("%1 %").arg(root._n(v, 1)) },
        skeletalMuscleKg: { label: Translation.tr("Skeletal muscle"), fmt: v => Translation.tr("%1 kg").arg(root._n(v, 1)) },
        leanMassKg: { label: Translation.tr("Lean mass"), fmt: v => Translation.tr("%1 kg").arg(root._n(v, 1)) },
        boneMassKg: { label: Translation.tr("Bone mass"), fmt: v => Translation.tr("%1 kg").arg(root._n(v, 1)) },
        bodyWaterKg: { label: Translation.tr("Body water"), fmt: v => Translation.tr("%1 kg").arg(root._n(v, 1)) },
        bmrKcal: { label: Translation.tr("Basal metabolic rate"), fmt: v => Translation.tr("%1 kcal").arg(root._n(v, 0)) },
        bmi: { label: Translation.tr("BMI"), fmt: v => root._n(v, 1) },
        m: { label: Translation.tr("Height"), fmt: v => Translation.tr("%1 m").arg(root._n(v, 2)) },
        systolic: { label: Translation.tr("Systolic"), fmt: v => Translation.tr("%1 mmHg").arg(root._n(v, 0)) },
        diastolic: { label: Translation.tr("Diastolic"), fmt: v => Translation.tr("%1 mmHg").arg(root._n(v, 0)) },
        pulse: { label: Translation.tr("Pulse"), fmt: v => Translation.tr("%1 bpm").arg(root._n(v, 0)) },
        mmolL: { label: Translation.tr("Glucose"), fmt: v => Translation.tr("%1 mmol/L").arg(root._n(v, 1)) },
        c: { label: Translation.tr("Temperature"), fmt: v => Translation.tr("%1 °C").arg(root._n(v, 1)) },
        mlKgMin: { label: Translation.tr("VO₂ max"), fmt: v => Translation.tr("%1 ml/kg/min").arg(root._n(v, 1)) }
    })

    /// A measurement field's name ("weightKg" → "Weight"); unknown fields keep theirs.
    function fieldLabel(field: string): string {
        return root.fields[field]?.label ?? field;
    }

    function formatField(field: string, value: var): string {
        if (typeof value !== "number" || !isFinite(value))
            return String(value ?? "–");
        const f = root.fields[field]?.fmt;
        return f ? f(value) : root._n(value, Number.isInteger(value) ? 0 : 1);
    }

    // ── Workout types ───────────────────────────────────────────────────
    // Health Connect's EXERCISE_TYPE_* names in lower snake case; the rest read as written.

    readonly property var exerciseTypes: ({
        walking: { label: Translation.tr("Walking"), icon: "directions_walk" },
        running: { label: Translation.tr("Running"), icon: "directions_run" },
        running_treadmill: { label: Translation.tr("Treadmill"), icon: "directions_run" },
        biking: { label: Translation.tr("Cycling"), icon: "directions_bike" },
        biking_stationary: { label: Translation.tr("Indoor cycling"), icon: "directions_bike" },
        hiking: { label: Translation.tr("Hiking"), icon: "hiking" },
        strength_training: { label: Translation.tr("Strength training"), icon: "fitness_center" },
        weightlifting: { label: Translation.tr("Weightlifting"), icon: "fitness_center" },
        swimming_pool: { label: Translation.tr("Swimming"), icon: "pool" },
        swimming_open_water: { label: Translation.tr("Open water swimming"), icon: "pool" },
        yoga: { label: Translation.tr("Yoga"), icon: "self_improvement" },
        rowing_machine: { label: Translation.tr("Rowing machine"), icon: "rowing" },
        stair_climbing: { label: Translation.tr("Stair climbing"), icon: "stairs" },
        other: { label: Translation.tr("Workout"), icon: "exercise" }
    })

    function exerciseLabel(type: string): string {
        const t = root.exerciseTypes[type];
        if (t)
            return t.label;
        const s = String(type ?? "").replace(/_/g, " ");
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : root.exerciseTypes.other.label;
    }

    function exerciseIcon(type: string): string {
        return root.exerciseTypes[type]?.icon ?? "exercise";
    }
}
