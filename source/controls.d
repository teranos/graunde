module controls;

public import hooks;
import proto : parsePbt, buildScopes, ScopeSet;

// --- Parsed pbt (CTFE) ---
// Pre-build: cat controls/*.pbt > .ctfe/sand

enum allParsed = parsePbt(import(".ctfe/sand"));

// --- Handler resolvers (CTFE) ---

CheckFn resolveCheck(string name) {
    switch (name) {
        case "binaryShadowed": return &binaryShadowed;
        default: return null;
    }
}

DelayFn resolveDelay(string name) {
    switch (name) {
        case "ciDelay": return &ciDelay;
        default: return null;
    }
}

DeliverFn resolveDeliver(string name) {
    switch (name) {
        case "ciDeliver": return &ciDeliver;
        default: return null;
    }
}

// --- Scope arrays (CTFE) ---

// TODO: catch hardcoded URLs in error messages that claim to report runtime values

private static immutable _preToolSet = buildScopes!(resolveCheck, resolveDelay, resolveDeliver)(allParsed, "PreToolUse");
static immutable allScopes = _preToolSet.items[0 .. _preToolSet.len];

private static immutable _fileSet = buildScopes(allParsed, "PreToolUseFile");
static immutable fileScopes = _fileSet.items[0 .. _fileSet.len];

private static immutable _upSet = buildScopes(allParsed, "UserPromptSubmit");
static immutable userPromptScopes = _upSet.items[0 .. _upSet.len];

private static immutable _stopSet = buildScopes(allParsed, "Stop");
static immutable stopScopes = _stopSet.items[0 .. _stopSet.len];

private static immutable _ssSet = buildScopes!(resolveCheck)(allParsed, "SessionStart");
static immutable sessionStartScopes = _ssSet.items[0 .. _ssSet.len];

private static immutable _ptuSet = buildScopes(allParsed, "PostToolUse");
static immutable postToolUseScopes = _ptuSet.items[0 .. _ptuSet.len];

private static immutable _ptudSet = buildScopes!(resolveCheck, resolveDelay, resolveDeliver)(allParsed, "PostToolUseDeferred");
static immutable postToolUseDeferredScopes = _ptudSet.items[0 .. _ptudSet.len];

private static immutable _ptufSet = buildScopes(allParsed, "PostToolUseFailure");
static immutable postToolUseFailureScopes = _ptufSet.items[0 .. _ptufSet.len];

private static immutable _pcSet = buildScopes(allParsed, "PreCompact");
static immutable preCompactScopes = _pcSet.items[0 .. _pcSet.len];

// --- Handler functions ---

int ciDelay(const(char)[] cwd) {
    import deferred : getCIAvgDuration, computeDelay;
    import sqlite : getBranch;
    auto branch = getBranch(cwd);
    if (branch is null) return 60;
    return computeDelay(getCIAvgDuration(cwd, branch));
}

const(char)[] ciDeliver(const(char)[] cwd) {
    import deferred : checkCIStatus;
    import sqlite : getBranch;
    auto branch = getBranch(cwd);
    if (branch is null) return null;
    return checkCIStatus(cwd, branch);
}

// --- Check functions for sessionstart() controls ---

extern (C) int access(const(char)* path, int mode);

bool binaryShadowed(const(char)[] cwd) {
    enum F_OK = 0;
    return access("/usr/local/bin/graunde\0".ptr, F_OK) == 0;
}
