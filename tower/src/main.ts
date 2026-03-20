import { mount } from "svelte";
import App from "./App.svelte";
import { parseTextproto, type ParseResult } from "./parse.js";

const TEXTPROTO_FILES = [
  "controls/controls.textproto",
  "controls/qntx.textproto",
  "controls/macos.textproto",
];

type FireData = Record<string, {
  count: number;
  lastFired: string | null;
  recent: { session: string; cwd: string; timestamp: string }[];
}>;

async function init() {
  const [files, firesRes] = await Promise.all([
    Promise.all(
      TEXTPROTO_FILES.map(async (path) => {
        const res = await fetch(`/${path}`);
        if (!res.ok) return null;
        const text = await res.text();
        const name = path.split("/").pop()!.replace(".textproto", "");
        return parseTextproto(text, name);
      })
    ),
    fetch("/api/fires").then(r => r.ok ? r.json() : {}).catch(() => ({})),
  ]);

  const parsed = files.filter((f): f is ParseResult => f !== null);
  const fires = firesRes as FireData;

  mount(App, {
    target: document.getElementById("app")!,
    props: { files: parsed, fires },
  });

  const sse = new EventSource("/api/events");
  sse.onmessage = (e) => {
    if (e.data === "reload") location.reload();
  };
}

init();
