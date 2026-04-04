module posttooluse_test;

import posttooluse : postToolUseMatch;
import hooks : Control, Cmd, Msg, FilePath, Tool;

// --- cmd matching (existing behavior) ---

enum cmdCtrl = () { Control c; c.cmd = Cmd("git commit"); c.msg = Msg("push follows"); return c; }();
static assert(postToolUseMatch(cmdCtrl, "git commit -m \"fix\"", null));
static assert(!postToolUseMatch(cmdCtrl, "git push", null));

// --- filepath matching (new behavior) ---

enum fpCtrl = () { Control c; c.filepath = FilePath(".pbt"); c.msg = Msg("Run make install"); return c; }();
static assert(postToolUseMatch(fpCtrl, null, "/Users/me/ground/controls/permissions.pbt"));
static assert(!postToolUseMatch(fpCtrl, null, "/Users/me/ground/source/main.d"));
static assert(!postToolUseMatch(fpCtrl, null, null));

// --- tool-name filtering ---

// filepath + tool filter — only fires for Edit
enum editOnlyCtrl = () { Control c; c.tool = Tool("Edit"); c.filepath = FilePath(".pbt"); c.msg = Msg("Rebuild"); return c; }();
static assert(postToolUseMatch(editOnlyCtrl, null, "/Users/me/ground/controls/permissions.pbt", "Edit"));
static assert(!postToolUseMatch(editOnlyCtrl, null, "/Users/me/ground/controls/permissions.pbt", "Read"));

// no tool filter — fires for any tool
static assert(postToolUseMatch(fpCtrl, null, "/Users/me/ground/controls/permissions.pbt", "Read"));
static assert(postToolUseMatch(fpCtrl, null, "/Users/me/ground/controls/permissions.pbt", "Edit"));
