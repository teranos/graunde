module main;

import std.json;
import std.stdio;
import matcher;

int run() {
    string input;
    try {
        foreach (line; stdin.byLineCopy)
            input ~= line;
    } catch (Exception) {
        stderr.writeln("graunde: failed to read stdin");
        return 1;
    }

    if (input.length == 0) {
        stderr.writeln("graunde: empty stdin");
        return 1;
    }

    JSONValue json;
    try {
        json = parseJSON(input);
    } catch (Exception) {
        stderr.writeln("graunde: invalid JSON on stdin");
        return 1;
    }

    string command;
    try {
        command = json["tool_input"]["command"].str;
    } catch (Exception) {
        stderr.writeln("graunde: missing tool_input.command");
        return 1;
    }

    auto result = checkCommand(command);

    if (result.control is null) {
        return 0;
    }

    auto amended = applyArg(result.control, result.segment);
    auto fullCommand = command;

    if (amended != result.segment) {
        import std.string : indexOf;
        auto idx = fullCommand.indexOf(result.segment);
        if (idx >= 0) {
            fullCommand = fullCommand[0 .. idx] ~ amended ~ fullCommand[idx + result.segment.length .. $];
        }
    }

    auto response = JSONValue([
        "hookSpecificOutput": JSONValue([
            "hookEventName": JSONValue("PreToolUse"),
            "permissionDecision": JSONValue("allow"),
            "updatedInput": JSONValue([
                "command": JSONValue(fullCommand)
            ])
        ])
    ]);

    stdout.writeln(response.toString());
    return 0;
}

void main() {
    import core.stdc.stdlib : exit;
    exit(run());
}
