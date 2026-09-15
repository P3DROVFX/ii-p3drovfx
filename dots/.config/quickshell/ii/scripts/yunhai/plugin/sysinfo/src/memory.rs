use crate::sysfs;

#[derive(Default)]
pub struct Sample {
    pub total: f64,
    pub used: f64,
    pub free: f64,
    pub usage: f64,
    pub swap_total: f64,
    pub swap_used: f64,
    pub swap_free: f64,
    pub swap_usage: f64,
}

fn ratio(used: f64, total: f64) -> f64 {
    if total > 0.0 {
        used / total
    } else {
        0.0
    }
}

pub fn sample() -> Option<Sample> {
    let text = sysfs::read_text("/proc/meminfo")?;
    let field = |key: &str| {
        text.lines()
            .find_map(|line| {
                let (name, rest) = line.split_once(':')?;
                (name == key).then(|| rest.split_whitespace().next()?.parse::<f64>().ok())?
            })
            .unwrap_or_default()
    };

    let total = field("MemTotal");
    let free = field("MemAvailable");
    let swap_total = field("SwapTotal");
    let swap_free = field("SwapFree");

    let used = (total - free).max(0.0);
    let swap_used = (swap_total - swap_free).max(0.0);

    Some(Sample {
        total,
        used,
        free,
        usage: ratio(used, total),
        swap_total,
        swap_used,
        swap_free,
        swap_usage: ratio(swap_used, swap_total),
    })
}
