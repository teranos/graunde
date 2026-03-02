module controls;

struct Cmd {
    string value;
}

struct Arg {
    string value;
}

struct Omit {
    string value;
}

struct Msg {
    string value;
}

Cmd cmd(string s) { return Cmd(s); }
Arg arg(string s) { return Arg(s); }
Omit omit(string s) { return Omit(s); }
Msg msg(string s) { return Msg(s); }

struct Control {
    string name;
    Cmd cmd;
    Arg arg;
    Omit omit;
    Msg msg;
}

Control control(string name, Cmd c, Arg a, Msg m) {
    return Control(name, c, a, Omit(""), m);
}

Control control(string name, Cmd c, Omit o, Msg m) {
    return Control(name, c, Arg(""), o, m);
}

// Msg-only control — matches but doesn't amend.
Control control(string name, Cmd c, Msg m) {
    return Control(name, c, Arg(""), Omit(""), m);
}

// Groups controls by scope and decision.
// Empty path = fires everywhere. Non-empty = cwd must contain the path.
// Decision: "allow" auto-approves, "ask" shows the permission prompt.
struct Scope {
    string path;
    string decision;
    const(Control)[] controls;
}

static immutable universal = [
    control("no-skip-hooks", cmd("git"), omit("--no-verify"),
        msg("Git hooks must not be bypassed, ever..")),
];

static immutable checkpoints = [
    control("commit-checkpoint", cmd("git commit"),
        msg("Commit requires manual approval")),
    control("pr-checkpoint", cmd("gh pr create"),
        msg("PR creation requires manual approval")),
];

static immutable qntx = [
    control("go-test-args", cmd("go test"), arg(`-tags "rustsqlite,qntxwasm" -short`),
        msg("Build tags and -short are required for go test in QNTX")),
];

static immutable allScopes = [
    Scope("", "allow", universal),
    Scope("", "ask", checkpoints),
    Scope("/QNTX", "allow", qntx),
];
