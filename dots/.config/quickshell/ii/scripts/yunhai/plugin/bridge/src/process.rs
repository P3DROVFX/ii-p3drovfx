#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!(<QtCore/QAbstractListModel>);
        type QAbstractListModel;

        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[base = QAbstractListModel]
        #[qproperty(i32, count, READ, NOTIFY)]
        #[qproperty(i32, total_count, cxx_name = "totalCount", READ, NOTIFY)]
        #[qproperty(bool, warming_up, cxx_name = "warmingUp", READ, NOTIFY)]
        #[qproperty(QString, filter, READ, WRITE = set_filter, NOTIFY)]
        #[qproperty(i32, sort_key, cxx_name = "sortKey", READ, WRITE = set_sort_key, NOTIFY)]
        #[qproperty(
            bool,
            sort_descending,
            cxx_name = "sortDescending",
            READ,
            WRITE = set_sort_descending,
            NOTIFY
        )]
        type ProcessTable = super::ProcessTableRust;
    }

    unsafe extern "RustQt" {
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &ProcessTable, parent: &QModelIndex) -> i32;

        #[cxx_override]
        fn data(self: &ProcessTable, index: &QModelIndex, role: i32) -> QVariant;

        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &ProcessTable) -> QHash_i32_QByteArray;

        #[cxx_name = "setFilter"]
        fn set_filter(self: Pin<&mut ProcessTable>, value: QString);

        #[cxx_name = "setSortKey"]
        fn set_sort_key(self: Pin<&mut ProcessTable>, value: i32);

        #[cxx_name = "setSortDescending"]
        fn set_sort_descending(self: Pin<&mut ProcessTable>, value: bool);

        #[qinvokable]
        fn refresh(self: Pin<&mut ProcessTable>);

        #[qinvokable]
        #[cxx_name = "killProcess"]
        fn kill_process(self: Pin<&mut ProcessTable>, pid: i32);

        #[qinvokable]
        #[cxx_name = "forceKillProcess"]
        fn force_kill_process(self: Pin<&mut ProcessTable>, pid: i32);
    }

    unsafe extern "RustQt" {
        #[cxx_name = "beginInsertRows"]
        #[inherit]
        fn begin_insert_rows(
            self: Pin<&mut ProcessTable>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[cxx_name = "endInsertRows"]
        #[inherit]
        fn end_insert_rows(self: Pin<&mut ProcessTable>);

        #[cxx_name = "beginRemoveRows"]
        #[inherit]
        fn begin_remove_rows(
            self: Pin<&mut ProcessTable>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );

        #[cxx_name = "endRemoveRows"]
        #[inherit]
        fn end_remove_rows(self: Pin<&mut ProcessTable>);

        #[cxx_name = "index"]
        #[inherit]
        fn model_index(
            self: &ProcessTable,
            row: i32,
            column: i32,
            parent: &QModelIndex,
        ) -> QModelIndex;

        #[cxx_name = "dataChanged"]
        #[inherit]
        fn data_changed(
            self: Pin<&mut ProcessTable>,
            top_left: &QModelIndex,
            bottom_right: &QModelIndex,
            roles: &QList_i32,
        );
    }
}

use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::{
    QByteArray, QHash, QHashPair_i32_QByteArray, QList, QModelIndex, QString, QVariant,
};
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use sysinfo::{memory, process};

const ROLE_PID: i32 = 256;
const ROLE_NAME: i32 = ROLE_PID + 1;
const ROLE_COMMAND: i32 = ROLE_NAME + 1;
const ROLE_USER: i32 = ROLE_COMMAND + 1;
const ROLE_CPU_PERCENT: i32 = ROLE_USER + 1;
const ROLE_MEM_PERCENT: i32 = ROLE_CPU_PERCENT + 1;
const ROLE_MEMORY_FORMATTED: i32 = ROLE_MEM_PERCENT + 1;

const ROLES: [(i32, &str); 7] = [
    (ROLE_PID, "pid"),
    (ROLE_NAME, "name"),
    (ROLE_COMMAND, "fullCommand"),
    (ROLE_USER, "user"),
    (ROLE_CPU_PERCENT, "cpuPercent"),
    (ROLE_MEM_PERCENT, "memPercent"),
    (ROLE_MEMORY_FORMATTED, "memoryFormatted"),
];

const SORT_MEMORY: i32 = 1;
const SORT_NAME: i32 = 2;

struct Entry {
    pid: QString,
    name: QString,
    command: QString,
    user: QString,
    memory_formatted: QString,
    sort_name: String,
    search: String,
    cpu_percent: f64,
    mem_percent: f64,
    memory_kb: f64,
    cpu_ticks: u64,
    uid: Option<u32>,
    seen: bool,
}

impl Entry {
    fn new(raw: &process::Raw) -> Self {
        let command = process::command_line(raw.pid, &raw.comm);
        let name = process::display_name(&command);

        Self {
            pid: QString::from(&raw.pid.to_string()),
            sort_name: name.to_lowercase(),
            search: format!("{} {}", name.to_lowercase(), command.to_lowercase()),
            name: QString::from(&name),
            command: QString::from(&command),
            user: QString::default(),
            memory_formatted: QString::default(),
            cpu_percent: 0.0,
            mem_percent: 0.0,
            memory_kb: -1.0,
            cpu_ticks: raw.cpu_ticks,
            uid: None,
            seen: false,
        }
    }

    fn sample(&mut self, raw: &process::Raw, total_delta: u64, memory_total_kb: f64) {
        let ticks_delta = raw.cpu_ticks.saturating_sub(self.cpu_ticks);
        self.cpu_ticks = raw.cpu_ticks;
        self.cpu_percent = if total_delta > 0 {
            (ticks_delta as f64 / total_delta as f64 * 100.0).clamp(0.0, 100.0)
        } else {
            0.0
        };

        if self.uid != Some(raw.uid) {
            self.uid = Some(raw.uid);
            self.user = QString::from(&process::user_name(raw.uid));
        }

        if self.memory_kb != raw.rss_kb {
            self.memory_kb = raw.rss_kb;
            self.memory_formatted = QString::from(&process::format_memory(raw.rss_kb));
        }

        self.mem_percent = if memory_total_kb > 0.0 {
            raw.rss_kb / memory_total_kb * 100.0
        } else {
            0.0
        };
        self.seen = true;
    }

    fn matches(&self, filter: &str, pid: i32) -> bool {
        filter.is_empty() || self.search.contains(filter) || pid.to_string().contains(filter)
    }
}

pub struct ProcessTableRust {
    count: i32,
    total_count: i32,
    warming_up: bool,
    filter: QString,
    sort_key: i32,
    sort_descending: bool,
    entries: HashMap<i32, Entry>,
    rows: Vec<i32>,
    memory_total_kb: f64,
    last_total_ticks: u64,
}

impl Default for ProcessTableRust {
    fn default() -> Self {
        Self {
            count: 0,
            total_count: 0,
            warming_up: true,
            filter: QString::default(),
            sort_key: 0,
            sort_descending: true,
            entries: HashMap::new(),
            rows: Vec::new(),
            memory_total_kb: memory::sample()
                .map(|sample| sample.total)
                .unwrap_or_default(),
            last_total_ticks: 0,
        }
    }
}

impl qobject::ProcessTable {
    fn row_count(&self, _parent: &QModelIndex) -> i32 {
        self.rows.len() as i32
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let Some(entry) = usize::try_from(index.row())
            .ok()
            .and_then(|row| self.rows.get(row))
            .and_then(|pid| self.entries.get(pid))
        else {
            return QVariant::default();
        };

        match role {
            ROLE_PID => QVariant::from(&entry.pid),
            ROLE_NAME => QVariant::from(&entry.name),
            ROLE_COMMAND => QVariant::from(&entry.command),
            ROLE_USER => QVariant::from(&entry.user),
            ROLE_CPU_PERCENT => QVariant::from(&entry.cpu_percent),
            ROLE_MEM_PERCENT => QVariant::from(&entry.mem_percent),
            ROLE_MEMORY_FORMATTED => QVariant::from(&entry.memory_formatted),
            _ => QVariant::default(),
        }
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut names = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in ROLES {
            names.insert(role, QByteArray::from(name));
        }
        names
    }

    fn set_filter(mut self: Pin<&mut Self>, value: QString) {
        if self.filter == value {
            return;
        }
        self.as_mut().rust_mut().filter = value;
        self.as_mut().filter_changed();
        self.rebuild_view();
    }

    fn set_sort_key(mut self: Pin<&mut Self>, value: i32) {
        if self.sort_key == value {
            return;
        }
        self.as_mut().rust_mut().sort_key = value;
        self.as_mut().sort_key_changed();
        self.rebuild_view();
    }

    fn set_sort_descending(mut self: Pin<&mut Self>, value: bool) {
        if self.sort_descending == value {
            return;
        }
        self.as_mut().rust_mut().sort_descending = value;
        self.as_mut().sort_descending_changed();
        self.rebuild_view();
    }

    fn refresh(mut self: Pin<&mut Self>) {
        let total_ticks = process::total_cpu_ticks();
        let had_prior_sample = self.last_total_ticks != 0;
        let total_delta = total_ticks.saturating_sub(self.last_total_ticks);
        let memory_total_kb = self.memory_total_kb;

        for entry in self.as_mut().rust_mut().entries.values_mut() {
            entry.seen = false;
        }

        for raw in process::scan() {
            self.as_mut()
                .rust_mut()
                .entries
                .entry(raw.pid)
                .or_insert_with(|| Entry::new(&raw))
                .sample(&raw, total_delta, memory_total_kb);
        }

        let mut state = self.as_mut().rust_mut();
        state.entries.retain(|_, entry| entry.seen);
        state.last_total_ticks = total_ticks;

        if self.warming_up && had_prior_sample {
            self.as_mut().rust_mut().warming_up = false;
            self.as_mut().warming_up_changed();
        }

        self.rebuild_view();
    }

    fn kill_process(mut self: Pin<&mut Self>, pid: i32) {
        process::terminate(pid);
        self.as_mut().refresh();
    }

    fn force_kill_process(mut self: Pin<&mut Self>, pid: i32) {
        process::kill(pid);
        self.as_mut().refresh();
    }

    fn compare(&self, first: i32, second: i32) -> Ordering {
        let (Some(left), Some(right)) = (self.entries.get(&first), self.entries.get(&second))
        else {
            return first.cmp(&second);
        };

        match self.sort_key {
            SORT_NAME => left.sort_name.cmp(&right.sort_name),
            SORT_MEMORY => left.memory_kb.total_cmp(&right.memory_kb),
            _ => left.cpu_percent.total_cmp(&right.cpu_percent),
        }
        .then_with(|| first.cmp(&second))
    }

    fn visible_pids(&self) -> Vec<i32> {
        if self.warming_up {
            return Vec::new();
        }

        let filter = self.filter.to_string().to_lowercase();
        let mut pids: Vec<i32> = self
            .entries
            .iter()
            .filter(|(pid, entry)| entry.matches(&filter, **pid))
            .map(|(pid, _)| *pid)
            .collect();

        pids.sort_by(|first, second| {
            let (left, right) = if self.sort_descending {
                (second, first)
            } else {
                (first, second)
            };
            self.compare(*left, *right)
        });
        pids
    }

    fn rebuild_view(mut self: Pin<&mut Self>) {
        let next = self.visible_pids();

        self.as_mut()
            .remove_missing(&next.iter().copied().collect());
        self.as_mut().append_new(&next);
        self.as_mut().reorder(next);

        let count = self.rows.len() as i32;
        if self.count != count {
            self.as_mut().rust_mut().count = count;
            self.as_mut().count_changed();
        }

        let total = self.entries.len() as i32;
        if self.total_count != total {
            self.as_mut().rust_mut().total_count = total;
            self.as_mut().total_count_changed();
        }
    }

    fn remove_missing(mut self: Pin<&mut Self>, keep: &HashSet<i32>) {
        let mut row = self.rows.len();

        while row > 0 {
            let last = row - 1;
            if keep.contains(&self.rows[last]) {
                row = last;
                continue;
            }

            let mut first = last;
            while first > 0 && !keep.contains(&self.rows[first - 1]) {
                first -= 1;
            }

            self.as_mut()
                .begin_remove_rows(&QModelIndex::default(), first as i32, last as i32);
            self.as_mut().rust_mut().rows.drain(first..=last);
            self.as_mut().end_remove_rows();
            row = first;
        }
    }

    fn append_new(mut self: Pin<&mut Self>, next: &[i32]) {
        let listed: HashSet<i32> = self.rows.iter().copied().collect();
        let added: Vec<i32> = next
            .iter()
            .copied()
            .filter(|pid| !listed.contains(pid))
            .collect();
        if added.is_empty() {
            return;
        }

        let first = self.rows.len() as i32;
        let last = first + added.len() as i32 - 1;
        self.as_mut()
            .begin_insert_rows(&QModelIndex::default(), first, last);
        self.as_mut().rust_mut().rows.extend(added);
        self.as_mut().end_insert_rows();
    }

    fn reorder(mut self: Pin<&mut Self>, next: Vec<i32>) {
        if next.is_empty() {
            return;
        }

        self.as_mut().rust_mut().rows = next;

        let last = self.rows.len() as i32 - 1;
        let top_left = self.model_index(0, 0, &QModelIndex::default());
        let bottom_right = self.model_index(last, 0, &QModelIndex::default());
        self.data_changed(&top_left, &bottom_right, &QList::<i32>::default());
    }
}
