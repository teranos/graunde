module permissionrequest;

import core.stdc.stdio : stdout, fputs;
import parse : extractToolName, extractCommand, writeJsonString;
import permission : evaluatePermission, Decision;

int handlePermissionRequest(const(char)[] input, const(char)[] cwd, const(char)[] sessionId) {
    auto toolName = extractToolName(input);
    if (toolName is null) return 0;

    auto command = extractCommand(input);
    // For non-Bash tools command may be absent — use empty string
    if (command is null) command = "";

    import controls : permissionScopes;
    auto result = evaluatePermission(permissionScopes, cwd, toolName, command);

    if (result.decision == Decision.deny) {
        writeDenyResponse(result.msg);
        return 0;
    }

    if (result.decision == Decision.allow) {
        writeAllowResponse();
        return 0;
    }

    // Decision.ask or Decision.none — fall through to normal prompt
    return 0;
}

void writeAllowResponse() {
    fputs(`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}`, stdout);
    fputs("\n", stdout);
}

void writeDenyResponse(const(char)[] msg) {
    fputs(`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"`, stdout);
    if (msg.length > 0)
        writeJsonString(msg);
    fputs(`"}}}`, stdout);
    fputs("\n", stdout);
}
