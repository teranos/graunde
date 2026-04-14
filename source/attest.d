module attest;

import core.stdc.stdio : stderr, stdout, fputs, fwrite, fprintf, FILE;
import db : ZBuf;

extern (C) {
    FILE* popen(const(char)* command, const(char)* type);
    int pclose(FILE* stream);
    int mkstemp(char* tmpl);
    int close(int fd);
    long write(int fd, const(void)* buf, size_t count);
    int unlink(const(char)* path);
}

int handleAttest() {
    import controls : qntxNodes, attestations;

    if (qntxNodes.length == 0) {
        fputs("ground attest: no qntx nodes defined\n", stderr);
        return 0;
    }
    if (attestations.length == 0) {
        fputs("ground attest: no attestations defined\n", stderr);
        return 0;
    }

    int posted = 0;
    int failed = 0;

    foreach (ref node; qntxNodes) {
        foreach (ref a; attestations) {
            __gshared ZBuf body_;
            body_.reset();
            body_.put(`{"subjects":["`);
            body_.put(a.subject);
            body_.put(`"],"predicates":["`);
            body_.put(a.predicate);
            body_.put(`"],"contexts":["`);
            body_.put(a.context);
            body_.put(`"],"actors":["ground"]`);
            if (a.attributes.length > 0) {
                body_.put(`,"attributes":`);
                body_.put(a.attributes);
            }
            body_.put(`}`);

            // Write body to temp file to avoid shell injection
            __gshared char[32] tmpPath = "/tmp/ground-attest-XXXXXX\0\0\0\0\0\0\0";
            // Reset template each iteration
            foreach (i, c; "/tmp/ground-attest-XXXXXX\0")
                tmpPath[i] = c;

            auto fd = mkstemp(&tmpPath[0]);
            if (fd < 0) { failed++; continue; }

            auto bodySlice = body_.slice();
            write(fd, bodySlice.ptr, bodySlice.length);
            close(fd);

            __gshared ZBuf cmd;
            cmd.reset();
            cmd.put("curl -s --connect-timeout 0.4 --max-time 0.4 -o /dev/null -w '%{http_code}' -X POST ");
            cmd.put(node.url);
            cmd.put("/api/attestations -H 'Content-Type: application/json' -d @");
            cmd.put(tmpPath[0 .. 25]); // /tmp/ground-attest-XXXXXX
            cmd.put(" 2>/dev/null");
            cmd.putChar('\0');

            auto pipe = popen(cmd.ptr(), "r\0".ptr);
            if (pipe is null) {
                unlink(&tmpPath[0]);
                failed++;
                continue;
            }

            __gshared char[8] httpCode = 0;
            size_t n = 0;
            while (n < httpCode.length - 1) {
                auto r = fread(&httpCode[n], 1, 1, pipe);
                if (r == 0) break;
                n++;
            }
            pclose(pipe);
            unlink(&tmpPath[0]);

            // Report
            fputs("  ", stderr);
            fputs2(node.url);
            fputs(" ", stderr);
            fputs2(a.subject);
            fputs(" -> ", stderr);
            if (n >= 3 && httpCode[0] == '2') {
                fwrite(&httpCode[0], 1, n, stderr);
                fputs(" ok\n", stderr);
                posted++;
            } else if (n == 0) {
                fputs("unreachable\n", stderr);
                failed++;
            } else {
                fwrite(&httpCode[0], 1, n, stderr);
                fputs(" failed\n", stderr);
                failed++;
            }
        }
    }

    fprintf(stderr, "ground attest: %d posted, %d failed\n".ptr, posted, failed);
    return 0;
}

private void fputs2(const(char)[] s) {
    fwrite(s.ptr, 1, s.length, stderr);
}

private size_t fread(void* ptr, size_t size, size_t nmemb, FILE* stream) {
    import core.stdc.stdio : fread_ = fread;
    return fread_(ptr, size, nmemb, stream);
}
