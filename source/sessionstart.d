module sessionstart;

import core.stdc.stdio : stdout, fputs;
import matcher : contains;

// Only arch — Claude already receives Platform and OS Version from the environment.
version (X86_64) enum ARCH = "x86_64";
else version (AArch64) enum ARCH = "aarch64";
else enum ARCH = "unknown";

enum SESSION_CONTEXT = `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"arch: ` ~ ARCH ~ `"}}` ~ "\n";

// TODO: verify every event type's payload fields for rich string eligibility.
// Only UserPromptSubmit (prompt) and Stop (last_assistant_message) confirmed so far.
void attestTypes() {
    import sqlite : openDb, attestType, sqlite3_close;
    auto db = openDb();
    if (db is null) return;

    // Event types — <Type> is type of ClaudeCode
    static foreach (name; [
        "SessionStart", "PermissionRequest", "PreToolUse",
        "PostToolUse", "PostToolUseFailure", "Notification",
        "SubagentStart", "SubagentStop", "TeammateIdle",
        "TaskCompleted", "ConfigChange", "WorktreeCreate",
        "WorktreeRemove", "PreCompact", "Setup", "SessionEnd"
    ])
        attestType(db, name, "ClaudeCode", `{}`);

    attestType(db, "UserPromptSubmit", "ClaudeCode", `{"rich_string_fields":["prompt"]}`);
    attestType(db, "Stop", "ClaudeCode", `{"rich_string_fields":["last_assistant_message"]}`);

    // Grounded types — <Type> is type of Graunded
    attestType(db, "GraundedPreToolUse", "Graunded", `{}`);
    attestType(db, "GraundedStop", "Graunded", `{}`);
    attestType(db, "GraundedUserPromptSubmit", "Graunded", `{}`);

    sqlite3_close(db);
}

int handleSessionStart(const(char)[] source) {
    attestTypes();

    // Arch context on fresh starts only
    if (source is null || contains(source, "startup") || contains(source, "clear")) {
        fputs(SESSION_CONTEXT.ptr, stdout);
        return 0;
    }

    // TODO(#23): compact — re-inject session awareness lost in compaction
    // TODO(#24): resume — stale branch awareness after time away
    return 0;
}
