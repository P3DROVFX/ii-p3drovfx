//! Material Symbols for the app, drawn from the font the shell already uses.
//!
//! The shell names icons by Material Symbol (`"lock"`, `"sports_esports"`…) and the app
//! carries only a few as vectors. Rather than ship the whole font to the phone, the
//! phone asks for the names it lacks and gets each glyph's outline as SVG path data in
//! the 0–960 box the official SVGs use (y down), which Compose draws as a vector and
//! the app caches for good.
//!
//! A name is resolved the way text in the font is: its letters, then the ligature that
//! joins them (GSUB). Glyph names in `post` do not always match the symbol's name.

use std::fmt::Write as _;
use std::process::Command;
use std::sync::OnceLock;

use serde_json::{Map, Value};
use ttf_parser::gsub::SubstitutionSubtable;
use ttf_parser::{Face, GlyphId, OutlineBuilder};

/// At most this many names per request, each a plain symbol name.
pub const MAX_NAMES: usize = 64;

pub fn valid_name(name: &str) -> bool {
    !name.is_empty() && name.len() <= 64 && name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_')
}

/// The font file, found once through fontconfig.
fn font_path() -> Option<&'static str> {
    static PATH: OnceLock<Option<String>> = OnceLock::new();
    PATH.get_or_init(|| {
        let out = Command::new("fc-match").args(["-f", "%{file}", "Material Symbols Rounded"]).output().ok()?;
        let path = String::from_utf8(out.stdout).ok()?;
        (path.contains("MaterialSymbolsRounded") && std::path::Path::new(&path).exists()).then_some(path)
    })
    .as_deref()
}

/// `{name: path}` for every name the font has. The file is read for the request and
/// dropped after it: the helper keeps no font in memory between requests.
pub fn paths(names: &[String]) -> Map<String, Value> {
    let mut out = Map::new();
    let Some(path) = font_path() else { return out };
    let Ok(data) = std::fs::read(path) else { return out };
    let Ok(face) = Face::parse(&data, 0) else { return out };
    for name in names.iter().filter(|n| valid_name(n)).take(MAX_NAMES) {
        if let Some(d) = glyph(&face, name).and_then(|g| outline(&face, g)) {
            out.insert(name.clone(), Value::String(d));
        }
    }
    out
}

fn glyph(face: &Face, name: &str) -> Option<GlyphId> {
    let ids: Vec<GlyphId> = name.chars().map(|c| face.glyph_index(c)).collect::<Option<_>>()?;
    let (first, rest) = ids.split_first()?;
    let gsub = face.tables().gsub?;
    for lookup in gsub.lookups {
        for sub in lookup.subtables.into_iter::<SubstitutionSubtable>() {
            let SubstitutionSubtable::Ligature(lig) = sub else { continue };
            let Some(index) = lig.coverage.get(*first) else { continue };
            let Some(set) = lig.ligature_sets.get(index) else { continue };
            for l in set {
                if l.components.len() as usize == rest.len() && l.components.into_iter().eq(rest.iter().copied()) {
                    return Some(l.glyph);
                }
            }
        }
    }
    None
}

/// SVG path data, y flipped from the font's baseline-up units into the 960 box.
struct Svg(String);

impl Svg {
    fn pt(&mut self, x: f32, y: f32) {
        let _ = write!(self.0, "{} {} ", num(x), num(960.0 - y));
    }
}

fn num(v: f32) -> String {
    let r = (v * 10.0).round() / 10.0;
    if r.fract() == 0.0 { format!("{}", r as i32) } else { format!("{r:.1}") }
}

impl OutlineBuilder for Svg {
    fn move_to(&mut self, x: f32, y: f32) {
        self.0.push('M');
        self.pt(x, y);
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.0.push('L');
        self.pt(x, y);
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        self.0.push('Q');
        self.pt(x1, y1);
        self.pt(x, y);
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        self.0.push('C');
        self.pt(x1, y1);
        self.pt(x2, y2);
        self.pt(x, y);
    }
    fn close(&mut self) {
        self.0.push('Z');
    }
}

fn outline(face: &Face, glyph: GlyphId) -> Option<String> {
    let mut svg = Svg(String::new());
    face.outline_glyph(glyph, &mut svg)?;
    Some(svg.0.replace(" Z", "Z").trim_end().to_string())
}
