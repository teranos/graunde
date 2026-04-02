# Permissions — auto-allow/deny for permission dialogs

permission {
  tool: "Bash"
  allow: ["find *"]
}

permission {
  tool: "Bash"
  deny: ["sed *", "awk *"]
  msg: "Use Edit tool instead of sed/awk"
}

permission {
  tool: "Bash"
  allow: ["sleep *", "say *", "time *"]
}

permission {
  tool: "Bash"
  allow: ["cargo build*"]
}

permission {
  tool: "Bash"
  allow: [
    "gh run list*", "gh run view*", "gh run watch*",
    "gh issue list*", "gh issue view*", "gh release list*",
    "gh pr list*", "gh pr view*", "gh pr ready*"
  ]
}

permission {
  tool: "Read"
  deny: [".env", ".env.*", "secrets/*"]
  msg: "Secrets are off-limits"
}
