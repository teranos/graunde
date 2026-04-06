module control_handlers;

import matcher : contains;

// --- Check handlers ---
// bool function(cwd, input) — return true to fire the control.

extern (C) int access(const(char)* path, int mode);

bool binaryShadowed(const(char)[] cwd, const(char)[] input) {
    enum F_OK = 0;
    return access("/usr/local/bin/ground\0".ptr, F_OK) == 0;
}

bool strikethroughCheck(const(char)[] cwd, const(char)[] input) {
    import parse : extractNewString, extractToolName;
    auto toolName = extractToolName(input);
    if (toolName != "Edit") return false;
    auto newString = extractNewString(input);
    if (newString is null) return false;
    return contains(newString, "~~");
}

// --- Delay handlers ---
// int function(cwd) — return delay in seconds.

int ciDelay(const(char)[] cwd) {
    import deferred : getCIAvgDuration, computeDelay;
    import db : getBranch;
    auto branch = getBranch(cwd);
    if (branch is null) return 60;
    return computeDelay(getCIAvgDuration(cwd, branch));
}

// --- Deliver handlers ---
// const(char)[] function(cwd) — return message or null to suppress.

const(char)[] ciDeliver(const(char)[] cwd) {
    import deferred : checkCIStatus;
    import db : getBranch;
    auto branch = getBranch(cwd);
    if (branch is null) return null;
    return checkCIStatus(cwd, branch);
}

const(char)[] upstreamBriefingDeliver(const(char)[] cwd) {
    import db : popen, pclose, ZBuf;
    import core.stdc.stdio : fread, FILE;

    // Get upstream repo owner/name
    __gshared ZBuf repoCmd;
    repoCmd.reset();
    repoCmd.put("cd \"");
    repoCmd.put(cwd);
    repoCmd.put("\" && git remote get-url upstream 2>/dev/null");
    repoCmd.putChar('\0');

    auto repoPipe = popen(repoCmd.ptr(), "r");
    if (repoPipe is null) return null;

    __gshared char[256] repoBuf = 0;
    auto rn = fread(&repoBuf[0], 1, repoBuf.length - 1, repoPipe);
    pclose(repoPipe);
    if (rn == 0) return null;
    if (repoBuf[rn - 1] == '\n') rn--;
    if (rn == 0) return null;

    __gshared char[128] ownerRepo = 0;
    size_t orLen = 0;
    {
        auto url = repoBuf[0 .. rn];
        int lastGh = -1;
        foreach (i; 0 .. url.length) {
            if (i + 10 <= url.length && url[i .. i + 10] == "github.com")
                lastGh = cast(int) i;
        }
        if (lastGh < 0) return null;
        auto rest = url[lastGh + 10 .. $];
        if (rest.length > 0 && (rest[0] == '/' || rest[0] == ':'))
            rest = rest[1 .. $];
        if (rest.length > 4 && rest[$ - 4 .. $] == ".git")
            rest = rest[0 .. $ - 4];
        foreach (c; rest) {
            if (orLen < ownerRepo.length) ownerRepo[orLen++] = c;
        }
    }
    if (orLen == 0) return null;
    auto repo = ownerRepo[0 .. orLen];

    __gshared ZBuf ghCmd;
    ghCmd.reset();
    ghCmd.put("cd \"");
    ghCmd.put(cwd);
    ghCmd.put("\" && echo 'PRs:' && gh pr list -R ");
    ghCmd.put(repo);
    ghCmd.put(" --limit 10 --state all --json number,title,state --jq '.[] | \"#\\(.number) [\\(.state)] \\(.title)\"' 2>/dev/null");
    ghCmd.put(" && echo 'Issues:' && gh issue list -R ");
    ghCmd.put(repo);
    ghCmd.put(" --limit 10 --json number,title,state --jq '.[] | \"#\\(.number) [\\(.state)] \\(.title)\"' 2>/dev/null");
    ghCmd.put(" && echo 'Releases:' && gh release list -R ");
    ghCmd.put(repo);
    ghCmd.put(" --limit 3 2>/dev/null");
    ghCmd.put(" && echo 'Commits (missing):' && git fetch upstream 2>/dev/null && git log --oneline main..upstream/main 2>/dev/null");
    ghCmd.putChar('\0');

    auto pipe = popen(ghCmd.ptr(), "r");
    if (pipe is null) return null;

    __gshared char[3072] outBuf = 0;
    auto n = fread(&outBuf[0], 1, outBuf.length - 1, pipe);
    pclose(pipe);
    if (n == 0) return null;

    __gshared ZBuf result;
    result.reset();
    result.put("Upstream briefing (");
    result.put(repo);
    result.put("): ");
    result.put(outBuf[0 .. n]);
    return result.slice();
}
