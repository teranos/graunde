module matcher;

import controls;
import std.algorithm : canFind;
import std.array : array;
import std.string : strip, indexOf;

struct Match {
    const(Control)* control;
    string segment;
}

string[] splitSegments(string command) {
    string[] segments;
    string current;
    size_t i = 0;

    while (i < command.length) {
        if (command[i] == '|' || command[i] == ';') {
            if (current.strip.length > 0)
                segments ~= current.strip;
            current = "";
            i++;
        } else if (i + 1 < command.length && command[i] == '&' && command[i + 1] == '&') {
            if (current.strip.length > 0)
                segments ~= current.strip;
            current = "";
            i += 2;
        } else {
            current ~= command[i];
            i++;
        }
    }

    if (current.strip.length > 0)
        segments ~= current.strip;

    return segments;
}

Match checkCommand(string command) {
    auto segments = splitSegments(command);

    foreach (ref segment; segments) {
        foreach (ref c; allControls) {
            if (segment.canFind(c.cmd.value)) {
                return Match(&c, segment);
            }
        }
    }

    return Match(null, "");
}

string applyArg(const Control* c, string segment) {
    auto cmdVal = c.cmd.value;
    auto idx = segment.indexOf(cmdVal);
    if (idx < 0) return segment;

    auto insertAt = idx + cmdVal.length;
    return segment[0 .. insertAt] ~ " " ~ c.arg.value ~ segment[insertAt .. $];
}

// --- Major Tom's test suite ---

unittest {
    // Major Tom runs a simple command — one segment
    auto segments = splitSegments("go test ./...");
    assert(segments == ["go test ./..."]);
}

unittest {
    // Major Tom pipes and chains — three segments
    auto segments = splitSegments("echo hello | go test ./... && make build");
    assert(segments == ["echo hello", "go test ./...", "make build"]);
}

unittest {
    // Major Tom runs "go test" — Graunde Control catches it
    auto result = checkCommand("go test ./...");
    assert(result.control !is null);
    assert(result.control.name == "go-test-args");
}

unittest {
    // Major Tom runs "ls -la" — Graunde Control lets it pass
    auto result = checkCommand("ls -la");
    assert(result.control is null);
}

unittest {
    // Major Tom forgets build tags — Graunde Control amends
    auto result = checkCommand("go test ./...");
    auto amended = applyArg(result.control, result.segment);
    assert(amended == `go test -tags "rustsqlite,qntxwasm" -short ./...`);
}

unittest {
    // Major Tom hides "go test" in a pipe — still caught, args preserved
    auto result = checkCommand("echo hello | go test -v ./cmd/qntx");
    assert(result.control !is null);
    auto amended = applyArg(result.control, result.segment);
    assert(amended == `go test -tags "rustsqlite,qntxwasm" -short -v ./cmd/qntx`);
}
