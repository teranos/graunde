module sessionstart;

import core.stdc.stdio : stdout, fputs;

// Only arch — Claude already receives Platform and OS Version from the environment.
version (X86_64) enum ARCH = "x86_64";
else version (AArch64) enum ARCH = "aarch64";
else enum ARCH = "unknown";

enum SESSION_CONTEXT = `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"arch: ` ~ ARCH ~ `"}}` ~ "\n";

int handleSessionStart() {
    fputs(SESSION_CONTEXT.ptr, stdout);
    return 0;
}
