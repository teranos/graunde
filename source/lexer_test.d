module lexer_test;

import lexer : skipWS, skipLine, expect, splitMode, readWord, readValue, parseInt;

// --- splitMode ---

enum sm1 = splitMode("control.w");
static assert(sm1.base == "control");
static assert(sm1.mode == "w");

enum sm2 = splitMode("control.rw");
static assert(sm2.base == "control");
static assert(sm2.mode == "rw");

enum sm3 = splitMode("permission.r");
static assert(sm3.base == "permission");
static assert(sm3.mode == "r");

enum sm4 = splitMode("scope");
static assert(sm4.base == "scope");
static assert(sm4.mode == "");

// --- parseInt ---

static assert(parseInt("42") == 42);
static assert(parseInt("0") == 0);
static assert(parseInt("-1") == -1);
static assert(parseInt("604800") == 604800);

// --- readWord ---

enum rwInput = "control.w {";
enum rwResult = () {
    string s = rwInput;
    size_t pos = 0;
    auto w = readWord(s, pos);
    return w;
}();
static assert(rwResult == "control.w");

// --- readValue ---

// Quoted string
enum rvQuoted = () {
    string s = `"hello world" rest`;
    size_t pos = 0;
    return readValue(s, pos);
}();
static assert(rvQuoted == "hello world");

// Backtick string
enum rvBacktick = () {
    string s = "`has \"quotes\"` rest";
    size_t pos = 0;
    return readValue(s, pos);
}();
static assert(rvBacktick == `has "quotes"`);

// List start — returns null
enum rvList = () {
    string s = `["a", "b"]`;
    size_t pos = 0;
    return readValue(s, pos);
}();
static assert(rvList is null);

// Unquoted value
enum rvUnquoted = () {
    string s = "true\n";
    size_t pos = 0;
    return readValue(s, pos);
}();
static assert(rvUnquoted == "true");

// --- skipWS ---

enum swResult = () {
    string s = "  \t\nhello";
    size_t pos = 0;
    skipWS(s, pos);
    return pos;
}();
static assert(swResult == 4);

// --- skipLine ---

enum slResult = () {
    string s = "# comment\nnext";
    size_t pos = 0;
    skipLine(s, pos);
    return pos;
}();
static assert(slResult == 10);
