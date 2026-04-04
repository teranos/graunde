module posttooluse;

import matcher : hasSegment, contains;
import hooks : Control, scopeMatches;
import parse : extractCommand, extractFilePath, extractToolName, writeJsonString;
import core.stdc.stdio : stdout, fputs;

// Matches a PostToolUse control against a command and/or file path.
// Returns true if the control should fire.
bool postToolUseMatch(const Control c, const(char)[] command, const(char)[] filePath,
    const(char)[] toolName = null)
{
    if (c.tool.value.length > 0 && (toolName.length == 0 || toolName != c.tool.value))
        return false;
    if (c.cmd.value.length > 0 && command.length > 0 && hasSegment(command, c.cmd.value))
        return true;
    if (c.filepath.value.length > 0 && filePath.length > 0 && contains(filePath, c.filepath.value))
        return true;
    return false;
}

int handlePostToolUse(const(char)[] input, const(char)[] cwd, const(char)[] sessionId) {
    auto command = extractCommand(input);
    auto filePath = extractFilePath(input);
    auto toolName = extractToolName(input);
    auto detail = command !is null ? command : (filePath !is null ? filePath : cast(const(char)[])"PostToolUse");

    // Check PostToolUse controls
    {
        import controls : postToolUseScopes;
        foreach (ref scope_; postToolUseScopes) {
            if (!scopeMatches(scope_.path, cwd)) continue;
            foreach (ref c; scope_.controls) {
                if (postToolUseMatch(c, detail, filePath, toolName) && c.msg.value.length > 0) {
                    {
                        import sqlite : attestControlFire;
                        attestControlFire(null, "GroundedPostToolUse", c.name, cwd, sessionId);
                    }
                    fputs(`{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"`, stdout);
                    writeJsonString(c.msg.value);
                    fputs(`"}}`, stdout);
                    fputs("\n", stdout);
                    return 0;
                }
            }
        }
    }

    // Check deferred PostToolUse controls
    {
        import controls : postToolUseDeferredScopes;
        foreach (ref scope_; postToolUseDeferredScopes) {
            if (!scopeMatches(scope_.path, cwd)) continue;
            foreach (ref c; scope_.controls) {
                if (c.cmd.value.length == 0 || !hasSegment(detail, c.cmd.value))
                    continue;
                if (c.trigger.len > 0) {
                    bool triggerHit = false;
                    foreach (ref v; c.trigger.values)
                        if (contains(detail, v)) { triggerHit = true; break; }
                    if (!triggerHit) continue;
                }

                import sqlite : openDb, sqlite3_close;
                import deferred : writeDeferredMessage;
                auto db = openDb();
                if (db is null) continue;

                auto delay = c.defer.delayFn !is null
                    ? c.defer.delayFn(cwd)
                    : c.defer.delaySec;
                writeDeferredMessage(db, c.name, cwd, sessionId, c.defer.msg, delay);

                {
                    import sqlite : attestControlFire;
                    attestControlFire(db, "GroundedPostToolUseDeferred", c.name, cwd, sessionId);
                }

                sqlite3_close(db);
            }
        }
    }

    return 0;
}
