module main;

// Hook output reference — graunde responds via exit code and optional JSON on stdout.
//
// Exit codes:
//   0     — action proceeds, stdout parsed for JSON
//   2     — action blocked, stderr fed to Claude as error
//   other — non-blocking error, action proceeds
//
// Top-level response fields:
//   continue           — (Stop) true makes Claude continue instead of stopping
//   suppressOutput     — suppress hook output from display
//   decision           — "approve" or "block"
//   reason             — explanation for the decision
//   systemMessage      — injected as system message to Claude
//   permissionDecision — "allow", "deny", or "ask"
//
// hookSpecificOutput (PreToolUse, UserPromptSubmit, PostToolUse):
//   hookEventName            — must match the event
//   permissionDecision       — (PreToolUse) "allow", "deny", or "ask"
//   permissionDecisionReason — (PreToolUse) shown to user (allow/ask) or Claude (deny)
//   updatedInput             — (PreToolUse) replaces tool input before execution
//   additionalContext        — (UserPromptSubmit required, PostToolUse optional) injected into context

import matcher : checkCommand, applyArg, applyOmit, checkFilePath, FileMatch, indexOf, contains, hasSegment, Buf;
import parse : extractCommand, extractCwd, extractSessionId, extractToolUseId, extractHookEventName, extractToolName, extractFilePath, extractSource, writeJsonString, fputs2;
import controls : HookEvent;
import core.stdc.stdio : stdin, stdout, stderr, fread, fputs, fprintf, fwrite, FILE;
import sqlite : popen, pclose;
import core.stdc.stdlib : exit;
import core.sys.posix.unistd : isatty;

extern (C) {
    struct timeval { long tv_sec; long tv_usec; }
    int gettimeofday(timeval* tv, void* tz);
}

long usecNow() {
    timeval tv;
    gettimeofday(&tv, null);
    return tv.tv_sec * 1_000_000 + tv.tv_usec;
}

// Extract PR number from "gh pr comment 39 ..." or "gh pr review 39 ..."
const(char)[] extractPrNumber(const(char)[] cmd) {
    foreach (prefix; ["gh pr comment ", "gh pr review "]) {
        auto idx = indexOf(cmd, prefix);
        if (idx < 0) continue;
        auto start = cast(size_t) idx + prefix.length;
        auto end = start;
        while (end < cmd.length && cmd[end] >= '0' && cmd[end] <= '9') end++;
        if (end > start) return cmd[start .. end];
    }
    return null;
}

// Parse hook_event_name string to HookEvent. CTFE-unrolled.
bool parseHookEvent(const(char)[] name, ref HookEvent event) {
    static foreach (member; __traits(allMembers, HookEvent)) {
        if (name == member) {
            event = __traits(getMember, HookEvent, member);
            return true;
        }
    }
    return false;
}

// Reads all of stdin into a static buffer.
// Returns the filled slice, or null on failure/empty.
const(char)[] readStdin() {
    __gshared char[65536] buf = 0;
    size_t total = 0;

    while (total < buf.length) {
        auto n = fread(&buf[total], 1, buf.length - total, stdin);
        if (n == 0) break;
        total += n;
    }

    if (total == 0) return null;
    return buf[0 .. total];
}

// Context-only response for non-Bash tools (no updatedInput).
void writeContextResponse(const(char)[] context, const(char)[] decision) {
    fputs(`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"`, stdout);
    fputs2(decision);
    fputs(`","additionalContext":"`, stdout);
    writeJsonString(context);
    fputs(`"}}`, stdout);
    fputs("\n", stdout);
}

void writeResponse(const(char)[] command, const(char)[] context, const(char)[] decision,
    bool background = false, int timeout = 0)
{
    fputs(`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"`, stdout);
    fputs2(decision);
    fputs(`","updatedInput":{"command":"`, stdout);
    writeJsonString(command);
    fputs(`"`, stdout);
    if (background)
        fputs(`,"run_in_background":true`, stdout);
    if (timeout > 0) {
        fputs(`,"timeout":`, stdout);
        // Write int as decimal
        char[16] tbuf = 0;
        int tlen = 0;
        int t = timeout;
        if (t == 0) { tbuf[0] = '0'; tlen = 1; }
        else {
            while (t > 0 && tlen < 15) { tbuf[tlen++] = cast(char)('0' + t % 10); t /= 10; }
            // Reverse
            foreach (i; 0 .. tlen / 2) { auto tmp = tbuf[i]; tbuf[i] = tbuf[tlen - 1 - i]; tbuf[tlen - 1 - i] = tmp; }
        }
        fwrite(&tbuf[0], 1, tlen, stdout);
    }
    fputs(`},"additionalContext":"`, stdout);
    writeJsonString(context);
    fputs(`"}}`, stdout);
    fputs("\n", stdout);
}

enum VERSION = import(".version");

void printVersion() {
    fputs("graunde ", stderr);
    // Print version without trailing newline from git describe
    foreach (c; VERSION)
        if (c != '\n' && c != '\r') {
            char[1] buf = c;
            fwrite(&buf[0], 1, 1, stderr);
        }
}

void printDuration(long t0) {
    auto elapsed = usecNow() - t0;
    auto ms = elapsed / 1000;
    auto us = elapsed % 1000;
    // Write "graunde: XXms" to stderr
    char[32] buf = 0;
    int pos = 0;
    // ms part
    if (ms == 0) { buf[pos++] = '0'; }
    else {
        char[10] digits = 0;
        int dLen = 0;
        auto v = ms;
        while (v > 0) { digits[dLen++] = cast(char)('0' + v % 10); v /= 10; }
        foreach (i; 0 .. dLen) buf[pos++] = digits[dLen - 1 - i];
    }
    buf[pos++] = '.';
    // us part — zero-padded to 3 digits
    buf[pos++] = cast(char)('0' + us / 100);
    buf[pos++] = cast(char)('0' + (us / 10) % 10);
    buf[pos++] = cast(char)('0' + us % 10);
    buf[pos++] = 'm';
    buf[pos++] = 's';
    fputs("graunde: ", stderr);
    fwrite(&buf[0], 1, pos, stderr);
    fputs("\n", stderr);
}

void recordTiming(long elapsedUs) {
    import sqlite : openDb, sqlite3_exec, sqlite3_prepare_v2, sqlite3_bind_int64,
                    sqlite3_step, sqlite3_finalize, sqlite3_close, sqlite3_stmt, SQLITE_OK;

    auto db = openDb();
    if (db is null) return;

    enum createSql = "CREATE TABLE IF NOT EXISTS timing (id INTEGER PRIMARY KEY, duration_us INTEGER NOT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP)\0";
    sqlite3_exec(db, createSql.ptr, null, null, null);

    enum sql = "INSERT INTO timing (duration_us) VALUES (?1)\0";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(db, sql.ptr, -1, &stmt, null) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, elapsedUs);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
    sqlite3_close(db);
}

extern (C) int main() {
    if (isatty(0)) {
        printVersion();
        fputs(" — Ground Control for Claude Code\n", stderr);
        return 0;
    }

    auto t0 = usecNow();
    auto rc = run();
    auto elapsed = usecNow() - t0;
    printDuration(t0);
    recordTiming(elapsed);
    return rc;
}

int run() {

    auto input = readStdin();
    if (input is null) {
        fputs("graunde: empty stdin\n", stderr);
        return 1;
    }

    // Common fields
    auto cwd = extractCwd(input);
    if (cwd is null) cwd = "";
    auto sessionId = extractSessionId(input);
    if (sessionId is null) sessionId = "";

    auto eventName = extractHookEventName(input);
    if (eventName is null) return 0;

    // Attest every event — even ones we don't handle yet
    {
        import sqlite : openDb, attestEvent, sqlite3_close;
        auto db = openDb();
        if (db !is null) {
            attestEvent(db, eventName, cwd, sessionId, input);
            sqlite3_close(db);
        }
    }

    HookEvent event;
    if (!parseHookEvent(eventName, event)) return 0;

    if (event == HookEvent.PreToolUse) {
        auto toolName = extractToolName(input);
        auto toolUseId = extractToolUseId(input);
        if (toolUseId is null) toolUseId = "unknown";

        auto command = extractCommand(input);

        if (command !is null) {
            // Bash — check controls
            auto result = checkCommand(command, cwd);

            if (result.control !is null) {
                // Msg-only control — no amendment, just decision + context

                if (result.control.arg.value.length == 0 && result.control.omit.value.length == 0) {
                    // Once per session: skip if already fired
                    import sqlite : openDb, attestationExists, attestEvent, sqlite3_close, ZBuf;
                    auto db = openDb();
                    if (db !is null) {
                        if (attestationExists(db, "GraundedPreToolUse", result.control.name, sessionId)) {
                            sqlite3_close(db);
                            // Still emit decision (e.g. "allow") — just skip the message
                            writeResponse(command, "", result.decision,
                                result.control.bg.value, result.control.tmo.value);
                            return 0;
                        }
                        __gshared ZBuf graundedAttrs;
                        graundedAttrs.reset();
                        graundedAttrs.put(`{"control":"`);
                        graundedAttrs.put(result.control.name);
                        graundedAttrs.put(`","decision":"`);
                        graundedAttrs.put(result.decision);
                        graundedAttrs.put(`"}`);
                        attestEvent(db, "GraundedPreToolUse", cwd, sessionId, graundedAttrs.slice());
                        sqlite3_close(db);
                    }
                    writeResponse(command, result.control.msg.value, result.decision,
                        result.control.bg.value, result.control.tmo.value);
                    return 0;
                }

                Buf amended;
                if (result.control.omit.value.length > 0)
                    amended = applyOmit(result.control, result.segment);
                else
                    amended = applyArg(result.control, result.segment);

                if (amended.slice() != result.segment) {
                    auto segIdx = indexOf(command, result.segment);
                    if (segIdx >= 0) {
                        Buf full;
                        full.put(command[0 .. cast(size_t) segIdx]);
                        full.put(amended.slice());
                        full.put(command[cast(size_t) segIdx + result.segment.length .. $]);
                        writeResponse(full.slice(), result.control.msg.value, result.decision,
                            result.control.bg.value, result.control.tmo.value);
                        return 0;
                    }
                }
                return 0;
            }

            return 0;
        }

        // Non-Bash tool (Edit/Write/Read/etc.) — check file-path controls
        // TODO: updatedInput for non-Bash tools (run_in_background, timeout, new_description)
        auto filePath = extractFilePath(input);
        if (filePath !is null) {
            auto fileResult = checkFilePath(filePath, cwd);
            if (fileResult.matched) {
                writeContextResponse(fileResult.msg, fileResult.decision);
                return 0;
            }
        }
        return 0;
    }

    // UserPromptSubmit — keyword controls
    if (event == HookEvent.UserPromptSubmit) {
        import userprompt : handleUserPromptSubmit;
        return handleUserPromptSubmit(input, cwd, sessionId);
    }

    // Stop — trail controls, deferred messages, lazy-verify
    if (event == HookEvent.Stop) {
        import stop : handleStop;
        return handleStop(input, cwd, sessionId);
    }

    // SessionStart — emit arch context on startup/clear
    if (event == HookEvent.SessionStart) {
        auto source = extractSource(input);
        import sessionstart : handleSessionStart;
        return handleSessionStart(source, cwd, sessionId);
    }

    // PreCompact — re-inject context that would be lost to compaction
    if (event == HookEvent.PreCompact) {
        import matcher : contains;
        import controls : preCompactScopes;
        bool first = true;

        fputs(`{"systemMessage":"`, stdout);

        foreach (ref scope_; preCompactScopes) {
            if (scope_.path.length > 0 && (cwd is null || !contains(cwd, scope_.path)))
                continue;
            foreach (ref c; scope_.controls) {
                if (!first) fputs(" | ", stdout);
                first = false;

                if (c.msg.value.length > 0)
                    fputs2(c.msg.value);

                if (c.cmd.value.length > 0) {
                    // Run cmd, append stdout (stripped of trailing newline)
                    __gshared char[4096] cmdBuf = 0;
                    __gshared char[1024] outBuf = 0;
                    if (c.cmd.value.length < cmdBuf.length) {
                        foreach (i, ch; c.cmd.value) cmdBuf[i] = ch;
                        cmdBuf[c.cmd.value.length] = 0;
                        auto pipe = popen(&cmdBuf[0], "r");
                        if (pipe !is null) {
                            auto n = fread(&outBuf[0], 1, outBuf.length, pipe);
                            pclose(pipe);
                            // Strip trailing newlines
                            while (n > 0 && (outBuf[n-1] == '\n' || outBuf[n-1] == '\r')) n--;
                            if (n > 0) fwrite(&outBuf[0], 1, n, stdout);
                        }
                    }
                }
            }
        }

        fputs(`"}`, stdout);
        fputs("\n", stdout);
        return 0;
    }

    // PostToolUse — controls + CI deferral
    if (event == HookEvent.PostToolUse) {
        auto detail = extractCommand(input);
        if (detail is null) detail = extractFilePath(input);
        if (detail is null) detail = eventName;

        // Check PostToolUse controls
        if (detail !is null) {
            import controls : postToolUseScopes;
            foreach (ref scope_; postToolUseScopes) {
                if (scope_.path.length > 0 && (cwd is null || !contains(cwd, scope_.path)))
                    continue;
                foreach (ref c; scope_.controls) {
                    if (c.cmd.value.length > 0 && hasSegment(detail, c.cmd.value) && c.msg.value.length > 0) {
                        fputs(`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"`, stdout);
                        import parse : writeJsonString;
                        writeJsonString(c.msg.value);
                        fputs(`"}}`, stdout);
                        fputs("\n", stdout);
                        return 0;
                    }
                }
            }
        }

        // After git push — defer CI check
        if (detail !is null && hasSegment(detail, "git push")) {
            import sqlite : openDb, getBranch, sqlite3_close, ZBuf;
            import deferred : writeDeferredMessage, getCIAvgDuration, computeDelay;
            auto db = openDb();
            if (db !is null) {
                auto branch = getBranch(cwd);
                if (branch !is null) {
                    auto delay = computeDelay(getCIAvgDuration(cwd, branch));
                    __gshared ZBuf msgBuf;
                    msgBuf.reset();
                    msgBuf.put("Check CI: gh run list --branch ");
                    msgBuf.put(branch);
                    msgBuf.put(" --limit 1");
                    writeDeferredMessage(db, "ci-check", cwd, sessionId, msgBuf.slice(), delay);
                }
                sqlite3_close(db);
            }
        }

        // After gh pr comment/review containing @claude review — defer reminder
        if (detail !is null && contains(detail, "gh pr") && contains(detail, "@claude review")) {
            import sqlite : openDb, sqlite3_close, ZBuf;
            import deferred : writeDeferredMessage;
            auto db = openDb();
            if (db !is null) {
                __gshared ZBuf reviewMsg;
                reviewMsg.reset();
                reviewMsg.put("Claude left a review comment. Check PR");
                auto prNum = extractPrNumber(detail);
                if (prNum.length > 0) {
                    reviewMsg.put(" #");
                    reviewMsg.put(prNum);
                }
                reviewMsg.put(" for @claude review comments.");
                writeDeferredMessage(db, "review-nudge", cwd, sessionId, reviewMsg.slice(), 300);
                sqlite3_close(db);
            }
        }

        return 0;
    }

    // PostToolUseFailure — contextual hints on failure
    if (event == HookEvent.PostToolUseFailure) {
        import parse : extractError;
        auto error = extractError(input);
        if (error !is null && contains(error, "No rule to make target")) {
            fputs(`{"systemMessage":"Run pwd — you may be in the wrong directory."}`, stdout);
            fputs("\n", stdout);
        }
        return 0;
    }

    // Unknown/unhandled events — exit 0, no output
    return 0;
}
