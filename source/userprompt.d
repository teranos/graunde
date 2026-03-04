module userprompt;

import main : extractJsonString, extractSessionId, buildEventId;
import matcher : contains;
import sqlite : ZBuf, openDb, attestationExists, writeAttestationTo, sqlite3_close;
import core.stdc.stdio : stdout, fputs, fwrite;

const(char)[] extractPrompt(const(char)[] json) {
    __gshared char[8192] buf = 0;
    return extractJsonString(json, `"prompt"`, &buf[0], buf.length);
}

enum GRAUNDE = `Graunde — a hook that fires on every hook event, tracks what happened in this session. Can rewrite PreToolUse hooks on the fly, nudges Claude Code into the right direction; https://github.com/teranos/graunde/tree/main`;
enum AX = `AX — attestation query, a natural-language-like syntax (Tim is tester of QNTX by attestor)`;

int handleUserPromptSubmit(const(char)[] input, const(char)[] cwd, const(char)[] sessionId) {
    auto prompt = extractPrompt(input);
    if (prompt is null) return 0;

    bool g = contains(prompt, "graunde") || contains(prompt, "Graunde");
    bool a = contains(prompt, " ax ") || contains(prompt, " AX ")
          || contains(prompt, " Ax ");

    if (!g && !a) return 0;

    // Check if already reminded in this session
    auto db = openDb();
    if (db !is null) {
        if (g && attestationExists(db, "graunde-reminder", sessionId))
            g = false;
        if (a && attestationExists(db, "ax-reminder", sessionId))
            a = false;
    }

    if (!g && !a) {
        if (db !is null) sqlite3_close(db);
        return 0;
    }

    // Build and emit response
    __gshared ZBuf ctx;
    ctx.reset();
    if (g) ctx.put(GRAUNDE);
    if (g && a) ctx.put(" | ");
    if (a) ctx.put(AX);

    fputs(`{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"`, stdout);
    fwrite(&ctx.data[0], 1, ctx.len, stdout);
    fputs(`"}}`, stdout);
    fputs("\n", stdout);

    // Attest so we don't fire again this session
    if (db !is null) {
        if (g)
            writeAttestationTo(db, "graunde-reminder", cwd, sessionId,
                buildEventId("graunde-reminder"), "graunde-reminder");
        if (a)
            writeAttestationTo(db, "ax-reminder", cwd, sessionId,
                buildEventId("ax-reminder"), "ax-reminder");
        sqlite3_close(db);
    }

    return 0;
}
