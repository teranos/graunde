module trail;

// TODO: branch story — query all attestations for the branch and produce a full
// narrative of what happened (edits, pushes, CI, reviews). Include in additionalContext
// on Stop so Claude has the complete picture, not just individual control checks.

import controls : Control, control, stop, Trigger, Msg, msg;
import db : sqlite3, sqlite3_stmt, sqlite3_prepare_v2, sqlite3_bind_text,
                sqlite3_step, sqlite3_finalize, sqlite3_column_text,
                SQLITE_OK, SQLITE_ROW, SQLITE_TRANSIENT, ZBuf;
import matcher : contains;

static immutable trailControls = [
    control("clippy-reminder", stop(),
        msg("Rust files edited after last cargo clippy run. Run cargo clippy before pushing.")),
];

struct TrailTiming {
    long rustCheckUs;
    long rsQueryUs;
    long reminderQueryUs;
    long clippyQueryUs;
    bool isRust;
    bool skippedEarly; // rs query returned 0, skipped rest
}

struct TrailMatch {
    const(Control)* control;
    const(char)[] reason;
    TrailTiming timing;
}

TrailMatch checkTrailControls(const(char)[] branch, sqlite3* db) {
    import stop : usecNow;
    TrailMatch result;

    foreach (ref c; trailControls) {
        if (c.name == "clippy-reminder") {
            import stop : g_cwd;
            auto t0 = usecNow();
            auto rust = isRustProject(g_cwd);
            result.timing.rustCheckUs = usecNow() - t0;
            result.timing.isRust = rust;
            if (!rust) continue;
            if (clippyMatch(db, branch, result.timing)) {
                result.control = &c;
                result.reason = c.msg.value;
                return result;
            }
        }
    }
    return result;
}

// Check if Cargo.toml exists in the working directory.
bool isRustProject(const(char)[] cwd) {
    if (cwd.length == 0) return false;
    __gshared char[512] pathBuf = 0;
    if (cwd.length + 11 >= pathBuf.length) return false;
    pathBuf[0 .. cwd.length] = cwd[];
    pathBuf[cwd.length .. cwd.length + 11] = "/Cargo.toml";
    pathBuf[cwd.length + 11] = 0;
    import core.sys.posix.sys.stat : stat_t, stat;
    stat_t st;
    return stat(&pathBuf[0], &st) == 0;
}

// --- clippy-reminder matching ---
// Queries attestation rows for the branch, tracks latest timestamps for
// .rs edits, cargo clippy runs, and clippy-reminder deliveries.
// Timestamps are ISO strings — lexicographic comparison suffices.

bool clippyMatch(sqlite3* db, const(char)[] branch, ref TrailTiming timing) {
    import db : buildSubject;
    import stop : usecNow;
    __gshared ZBuf subjectVal;
    import stop : g_cwd;
    buildSubject(subjectVal, g_cwd, branch);

    __gshared char[32] latestClippy = 0;
    __gshared char[32] latestRs = 0;
    __gshared char[32] latestReminder = 0;
    size_t clippyLen = 0;
    size_t rsLen = 0;
    size_t reminderLen = 0;

    // Latest .rs edit (Write or Edit)
    enum rsSql = "SELECT timestamp FROM attestations WHERE json_extract(subjects, '$[0]') = ?1 AND attributes LIKE '%.rs\"%' AND (attributes LIKE '%\"Write\"%' OR attributes LIKE '%\"Edit\"%') ORDER BY timestamp DESC LIMIT 1\0";
    auto t0 = usecNow();
    rsLen = queryLatestTs(db, rsSql, subjectVal, latestRs);
    timing.rsQueryUs = usecNow() - t0;
    if (rsLen == 0) { timing.skippedEarly = true; return false; }

    // Latest clippy-reminder delivery
    enum reminderSql = "SELECT timestamp FROM attestations WHERE json_extract(subjects, '$[0]') = ?1 AND attributes LIKE '%clippy-reminder%' ORDER BY timestamp DESC LIMIT 1\0";
    t0 = usecNow();
    reminderLen = queryLatestTs(db, reminderSql, subjectVal, latestReminder);
    timing.reminderQueryUs = usecNow() - t0;
    if (reminderLen > 0 && compareTs(latestReminder[0 .. reminderLen], latestRs[0 .. rsLen]) >= 0) return false;

    // Latest cargo clippy run
    enum clippySql = "SELECT timestamp FROM attestations WHERE json_extract(subjects, '$[0]') = ?1 AND attributes LIKE '%cargo clippy%' ORDER BY timestamp DESC LIMIT 1\0";
    t0 = usecNow();
    clippyLen = queryLatestTs(db, clippySql, subjectVal, latestClippy);
    timing.clippyQueryUs = usecNow() - t0;
    if (clippyLen == 0) return true;
    return compareTs(latestRs[0 .. rsLen], latestClippy[0 .. clippyLen]) > 0;
}

size_t queryLatestTs(sqlite3* db, const(char)* sql, ref ZBuf subjectVal, ref char[32] tsBuf) {
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, null) != SQLITE_OK)
        return 0;
    sqlite3_bind_text(stmt, 1, subjectVal.ptr(), cast(int) subjectVal.len, SQLITE_TRANSIENT);
    size_t len = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        auto tsPtr = sqlite3_column_text(stmt, 0);
        if (tsPtr !is null) {
            while (tsPtr[len] != 0 && len < 32) { tsBuf[len] = tsPtr[len]; len++; }
        }
    }
    sqlite3_finalize(stmt);
    return len;
}

void copyTs(const(char)[] src, ref char[32] dst) {
    foreach (i; 0 .. (src.length < 32 ? src.length : 32))
        dst[i] = src[i];
}

int compareTs(const(char)[] a, const(char)[] b) {
    auto len = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. len) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    if (a.length < b.length) return -1;
    if (a.length > b.length) return 1;
    return 0;
}
