module main;

import matcher : checkCommand, applyArg, applyOmit, checkFilePath, FileMatch, indexOf, contains, Buf;
import parse;
import controls : HookEvent;
import sqlite : writeAttestation;
import core.stdc.stdio : stdin, stdout, stderr, fread, fputs, fprintf, fwrite;
import core.stdc.stdlib : exit;
import core.sys.posix.unistd : isatty;

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
    __gshared char[8192] buf = 0;
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

void writeResponse(const(char)[] command, const(char)[] context, const(char)[] decision) {
    fputs(`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"`, stdout);
    fputs2(decision);
    fputs(`","updatedInput":{"command":"`, stdout);
    writeJsonString(command);
    fputs(`"},"additionalContext":"`, stdout);
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

extern (C) int main() {
    if (isatty(0)) {
        printVersion();
        fputs(" — Ground Control for Claude Code\n", stderr);
        return 0;
    }

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
                writeAttestation(result.control.name, cwd, sessionId, toolUseId, command);

                // Msg-only control — no amendment, just decision + context
                // TODO(#3): query branch story and append to context
                if (result.control.arg.value.length == 0 && result.control.omit.value.length == 0) {
                    writeResponse(command, result.control.msg.value, result.decision);
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
                        writeResponse(full.slice(), result.control.msg.value, result.decision);
                        return 0;
                    }
                }
                return 0;
            }

            // No control match — still attest the tool call
            writeAttestation(toolName !is null ? toolName : "Bash", cwd, sessionId, toolUseId, command);
            return 0;
        }

        // Non-Bash tool (Edit/Write/Read/etc.) — check file-path controls, then attest
        auto filePath = extractFilePath(input);
        writeAttestation(
            toolName !is null ? toolName : "unknown",
            cwd, sessionId, toolUseId,
            filePath !is null ? filePath : ""
        );

        if (filePath !is null) {
            auto fileResult = checkFilePath(filePath, cwd);
            if (fileResult.matched) {
                writeAttestation(fileResult.name, cwd, sessionId, toolUseId, filePath);
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

    // Stop — attest and check ax controls
    if (event == HookEvent.Stop) {
        import stop : handleStop;
        return handleStop(input, cwd, sessionId);
    }

    // SessionStart — attest and emit arch context on startup/clear
    if (event == HookEvent.SessionStart) {
        auto source = extractSource(input);
        auto id = buildEventId(eventName);
        writeAttestation(eventName, cwd, sessionId, id, source !is null ? source : eventName);
        import sessionstart : handleSessionStart;
        return handleSessionStart(source);
    }

    // Lifecycle events — attest and pass through
    if (event == HookEvent.PostToolUse || event == HookEvent.PreCompact) {
        auto toolUseId = extractToolUseId(input);
        auto id = toolUseId !is null ? toolUseId : buildEventId(eventName);
        auto detail = extractCommand(input);
        if (detail is null) detail = extractFilePath(input);
        if (detail is null) detail = eventName;
        writeAttestation(eventName, cwd, sessionId, id, detail);
    }

    // Unknown events — exit 0, no output
    return 0;
}
