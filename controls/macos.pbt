# macOS — graunde-scoped denials
scope {
  path: "/graunde"
  decision: "deny"
  event: "PreToolUse"

  control {
    name: "no-dub-test"
    cmd: "dub test"
    msg: "Do not run dub test locally — syspolicyd provenance check adds minutes to every recompilation on macOS. CI handles testing. Use make install directly."
  }
}

# macOS — UserPromptSubmit
scope {
  event: "UserPromptSubmit"

  control {
    name: "timer-reminder"
    userprompt: "timer for"
    msg: `You can set a timer on macOS. Run in background: sleep <seconds> && say "time" &`
  }
}

# macOS — Stop
scope {
  event: "Stop"

  control {
    name: "timer-capability"
    stop: ["can't set system timers", "can't set timers", "cannot set timers", "can't set a timer", "cannot set a timer"]
    msg: `You can set a timer. Run: sleep <seconds> && say "time" &`
  }
}
