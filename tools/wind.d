/// wind — pre-build tool that produces sand for ground's CTFE.
///
/// Concatenates controls/*.pbt and controls/local/*.pbt into .ctfe/sand.
/// Replaces: cat controls/*.pbt > .ctfe/sand; cat controls/local/*.pbt >> .ctfe/sand

import std.file : dirEntries, read, SpanMode, mkdirRecurse, exists, write;
import std.algorithm : sort;
import std.array : array;
import std.stdio : stderr;

void main() {
    mkdirRecurse(".ctfe");

    string sand;

    foreach (dir; ["controls", "controls/local"]) {
        if (!exists(dir)) continue;
        auto entries = dirEntries(dir, "*.pbt", SpanMode.shallow)
            .array
            .sort!((a, b) => a.name < b.name);
        foreach (entry; entries) {
            auto content = cast(string) read(entry.name);
            sand ~= content;
            if (sand.length > 0 && sand[$ - 1] != '\n')
                sand ~= '\n';
        }
    }

    write(".ctfe/sand", sand);
    stderr.writefln("wind: .ctfe/sand (%d bytes)", sand.length);
}
