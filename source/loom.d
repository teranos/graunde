module loom;

import sqlite : ZBuf;

// --- UDP send to loom ---

extern (C) {
    int socket(int domain, int type, int protocol);
    long sendto(int sockfd, const(void)* buf, size_t len, int flags,
                const(void)* dest_addr, uint addrlen);
    int close(int fd);
}

// sockaddr_in for IPv4
struct sockaddr_in {
    ubyte sin_len;
    ubyte sin_family;
    ushort sin_port;
    uint sin_addr;
    ubyte[8] sin_zero;
}

void sendToLoom(ref ZBuf subjects, ref ZBuf predicates, const(char)[] attributes) {
    // Build JSON: {"subjects":...,"predicates":...,"attributes":...}
    __gshared ZBuf pkt;
    pkt.reset();
    pkt.put(`{"subjects":`);
    pkt.put(subjects.slice());
    pkt.put(`,"predicates":`);
    pkt.put(predicates.slice());
    pkt.put(`,"attributes":`);
    // attributes may be raw JSON or a string — write it directly
    pkt.put(attributes);
    pkt.put("}");

    enum AF_INET = 2;
    enum SOCK_DGRAM = 2;
    enum LOOM_PORT = 19470;

    auto fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return;

    sockaddr_in addr;
    addr.sin_len = 16;
    addr.sin_family = AF_INET;
    addr.sin_port = (LOOM_PORT >> 8) | ((LOOM_PORT & 0xFF) << 8); // htons
    addr.sin_addr = 0x0100007F; // 127.0.0.1 in network byte order

    sendto(fd, pkt.ptr(), pkt.len, 0, &addr, addr.sizeof);
    close(fd);
}
