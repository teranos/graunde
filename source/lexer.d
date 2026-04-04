module lexer;

void skipWS(ref string s, ref size_t pos) {
    while (pos < s.length && (s[pos] == ' ' || s[pos] == '\t' || s[pos] == '\n' || s[pos] == '\r'))
        pos++;
}

void skipLine(ref string s, ref size_t pos) {
    while (pos < s.length && s[pos] != '\n') pos++;
    if (pos < s.length) pos++;
}

void expect(ref string s, ref size_t pos, char ch) {
    assert(pos < s.length && s[pos] == ch);
    pos++;
}

// Split "control.rw" into ("control", "rw"). No dot returns (word, "").
struct WordMode { string base; string mode; }
WordMode splitMode(string word) {
    foreach (i; 0 .. word.length) {
        if (word[i] == '.') return WordMode(word[0 .. i], word[i + 1 .. $]);
    }
    return WordMode(word, "");
}

string readWord(ref string s, ref size_t pos) {
    auto start = pos;
    while (pos < s.length && s[pos] != ' ' && s[pos] != '\t' && s[pos] != '\n'
            && s[pos] != '\r' && s[pos] != ':' && s[pos] != '{' && s[pos] != '}')
        pos++;
    assert(pos > start);
    return s[start .. pos];
}

string readValue(ref string s, ref size_t pos) {
    if (pos < s.length && s[pos] == '"')
        return readQuotedString(s, pos);
    if (pos < s.length && s[pos] == '`')
        return readBacktickString(s, pos);
    if (pos < s.length && s[pos] == '[') {
        pos++; // consume '['
        return null; // signal list to caller
    }
    // Unquoted value (true, false, integer)
    auto start = pos;
    while (pos < s.length && s[pos] != ' ' && s[pos] != '\t' && s[pos] != '\n'
            && s[pos] != '\r' && s[pos] != '}')
        pos++;
    return s[start .. pos];
}

// Double-quoted string — no escapes, returns input slice directly.
string readQuotedString(ref string s, ref size_t pos) {
    pos++; // skip opening quote
    auto start = pos;
    while (pos < s.length && s[pos] != '"')
        pos++;
    auto result = s[start .. pos];
    assert(pos < s.length);
    pos++; // skip closing quote
    return result;
}

// Backtick string — for values containing double quotes.
string readBacktickString(ref string s, ref size_t pos) {
    pos++; // skip opening backtick
    auto start = pos;
    while (pos < s.length && s[pos] != '`')
        pos++;
    auto result = s[start .. pos];
    assert(pos < s.length);
    pos++; // skip closing backtick
    return result;
}

int parseInt(string s) {
    int result = 0;
    bool neg = false;
    size_t i = 0;
    if (i < s.length && s[i] == '-') { neg = true; i++; }
    while (i < s.length && s[i] >= '0' && s[i] <= '9') {
        result = result * 10 + (s[i] - '0');
        i++;
    }
    return neg ? -result : result;
}
