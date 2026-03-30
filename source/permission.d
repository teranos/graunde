module permission;

import matcher : wildcardContains, stripQuoted;
import proto : ParseResult, ParsedPermission, parsePbt;

// --- Runtime permission structs ---

struct PatternList {
    string[16] _buf;
    ubyte len;
    const(string)[] values() const return { return _buf[0 .. len]; }
}

struct Permission {
    string tool;       // "Bash", "Write", "Edit", etc.
    PatternList allow;
    PatternList deny;
    PatternList ask;
    string msg;
}

struct PermissionScope {
    string path;
    const(Permission)[] permissions;
}

// --- Permission set (built at CTFE from parsed pbt) ---

struct PermissionSet {
    PermissionScope[32] items;
    Permission[128] permPool;
    size_t len;

    const(PermissionScope)[] opSlice() const return { return items[0 .. len]; }
}

PermissionSet buildPermissions(const ParseResult parsed) {
    PermissionSet result;
    size_t poolLen = 0;

    foreach (i; 0 .. parsed.scopeCount) {
        auto ps = &parsed.scopes[i];
        if (ps.permissionCount == 0) continue;

        auto permStart = poolLen;
        foreach (j; 0 .. ps.permissionCount) {
            auto pp = &ps.permissions[j];
            Permission p;
            p.tool = pp.tool;
            p.msg = pp.msg;

            p.allow._buf = pp.allow;
            p.allow.len = pp.allowCount;
            p.deny._buf = pp.deny;
            p.deny.len = pp.denyCount;
            p.ask._buf = pp.ask;
            p.ask.len = pp.askCount;

            assert(poolLen < result.permPool.length);
            result.permPool[poolLen] = p;
            poolLen++;
        }

        assert(result.len < result.items.length);
        result.items[result.len] = PermissionScope(ps.path, result.permPool[permStart .. poolLen]);
        result.len++;
    }
    return result;
}

// --- Permission evaluation ---
// Returns "deny", "ask", "allow", or null (no match — fall through).
// Precedence: deny > ask > allow.

enum Decision { none, allow, ask, deny }

struct PermissionResult {
    Decision decision;
    const(char)[] msg; // only set on deny
}

PermissionResult evaluatePermission(
    const(PermissionScope)[] scopes,
    const(char)[] cwd,
    const(char)[] toolName,
    const(char)[] command,
) {
    import hooks : scopeMatches;

    // Strip quoted content so patterns match commands, not their string arguments
    auto stripped = stripQuoted(command);
    auto cmd = stripped.slice;

    PermissionResult result;

    foreach (ref sc; scopes) {
        if (!scopeMatches(sc.path, cwd)) continue;

        foreach (ref p; sc.permissions) {
            if (p.tool.length > 0 && p.tool != toolName) continue;

            // Check deny first
            foreach (ref pat; p.deny.values) {
                if (wildcardContains(cmd, pat)) {
                    return PermissionResult(Decision.deny, p.msg);
                }
            }

            // Check ask
            foreach (ref pat; p.ask.values) {
                if (wildcardContains(cmd, pat)) {
                    if (result.decision < Decision.ask)
                        result.decision = Decision.ask;
                }
            }

            // Check allow
            foreach (ref pat; p.allow.values) {
                if (wildcardContains(cmd, pat)) {
                    if (result.decision < Decision.allow)
                        result.decision = Decision.allow;
                }
            }
        }
    }

    return result;
}

// --- CTFE tests ---

// Build + evaluate test via parsed pbt
enum testPermPbt = `
scope {
  path: "/"
  permission {
    tool: "Bash"
    allow: ["go build*", "go test*"]
    deny: ["*rm -rf*"]
    ask: ["*DELETE*"]
    msg: "Destructive op"
  }
}

scope {
  path: "/only-here"
  permission {
    tool: "Bash"
    allow: ["npm run*"]
  }
}
`;

enum testPermParsed = parsePbt(testPermPbt);
enum testPermSet = buildPermissions(testPermParsed);
static assert(testPermSet.len == 2);
static assert(testPermSet.items[0].path == "/");
static assert(testPermSet.items[0].permissions.length == 1);
static assert(testPermSet.items[0].permissions[0].tool == "Bash");
static assert(testPermSet.items[0].permissions[0].allow.len == 2);
static assert(testPermSet.items[0].permissions[0].deny.len == 1);
static assert(testPermSet.items[0].permissions[0].ask.len == 1);

// Allow match
enum r1 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", "go build ./...");
static assert(r1.decision == Decision.allow);

// No match
enum r2 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", "echo hello");
static assert(r2.decision == Decision.none);

// Deny wins — "rm -rf" matches deny even though nothing matches allow
enum r3 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", "rm -rf /tmp");
static assert(r3.decision == Decision.deny);
static assert(r3.msg == "Destructive op");

// Ask — "DELETE" matches ask
enum r4 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", "sqlite3 db DELETE FROM foo");
static assert(r4.decision == Decision.ask);

// Tool mismatch — Write tool, no Bash permissions apply
enum r5 = evaluatePermission(testPermSet[], "/home/user/project", "Write", "go build");
static assert(r5.decision == Decision.none);

// Scope mismatch — npm rule only in /only-here
enum r6 = evaluatePermission(testPermSet[], "/home/user/other", "Bash", "npm run test");
static assert(r6.decision == Decision.none);

// Scope match — npm rule fires in /only-here
enum r7 = evaluatePermission(testPermSet[], "/home/user/only-here", "Bash", "npm run test");
static assert(r7.decision == Decision.allow);

// Deny + allow in same permission — deny wins
enum r8 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", "go build && rm -rf /tmp");
static assert(r8.decision == Decision.deny);

// Quoted content ignored — "rm -rf" inside a commit message does NOT trigger deny
enum r9 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", `git commit -m "rm -rf cleanup"`);
static assert(r9.decision == Decision.none);

// Quoted content ignored — deny pattern in unquoted part still fires
enum r10 = evaluatePermission(testPermSet[], "/home/user/project", "Bash", `rm -rf /tmp && echo "done"`);
static assert(r10.decision == Decision.deny);
