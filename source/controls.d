module controls;

struct Cmd {
    string value;
}

struct Arg {
    string value;
}

Cmd cmd(string s) { return Cmd(s); }
Arg arg(string s) { return Arg(s); }

struct Control {
    string name;
    Cmd cmd;
    Arg arg;
}

Control control(string name, Cmd c, Arg a) {
    return Control(name, c, a);
}

enum allControls = [
    control("go-test-args", cmd("go test"), arg(`-tags "rustsqlite,qntxwasm" -short`)),
];
