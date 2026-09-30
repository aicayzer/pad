import { postToHost } from "./bridge";
import { PadEditor, type FormatCommand, type Keymap } from "./editor";
import "./style.css";

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number): void;
      reload(markdown: string, generation: number): void;
      markdown(): string | null;
      clipboard(): { text: string; html: string };
      format(command: FormatCommand, arg?: string | number): void;
      focus(): void;
      insertText(text: string, generation: number): boolean;
      keyDown(
        key: string,
        code: string,
        metaKey: boolean,
        ctrlKey: boolean,
        altKey: boolean,
        shiftKey: boolean,
        generation: number,
      ): boolean;
      find(text: string): void;
      insertPaths(paths: string[], x: number, y: number): void;
      setAccent(color: string): void;
      setTextSize(px: number): void;
      setKeymap(keymap: Keymap): void;
    };
  }
}

const root = document.getElementById("editor");
if (!root) throw new Error("editor root missing");

const formattedRoot = document.createElement("div");
root.append(formattedRoot);
const formatted = await PadEditor.mount(formattedRoot, {
  changed(markdown, generation) {
    postToHost({ type: "changed", markdown, generation });
  },
  stateChanged(state) {
    postToHost({ type: "state", ...state });
  },
  openLink(href) {
    postToHost({ type: "openLink", href });
  },
  copy(text) {
    postToHost({ type: "copy", text });
  },
});

const editor = formatted;
editor.setKeymap({
  bold: ["Mod-b"],
  italic: ["Mod-i"],
  code: ["Mod-e"],
  heading1: ["Mod-Alt-1"],
  heading2: ["Mod-Alt-2"],
  heading3: ["Mod-Alt-3"],
});
window.addEventListener("keydown", (event) => {
  if (
    event.metaKey &&
    !event.altKey &&
    !event.ctrlKey &&
    event.key.toLowerCase() === "k"
  ) {
    event.preventDefault();
    postToHost({ type: "requestLink" });
  }
});

// Links open on ⌘-click, so the pointer says so only while ⌘ is down.
for (const name of ["keydown", "keyup"] as const) {
  window.addEventListener(name, (event) =>
    document.documentElement.classList.toggle("meta", event.metaKey),
  );
}
window.addEventListener("blur", () =>
  document.documentElement.classList.remove("meta"),
);

window.editor = {
  load: (markdown, generation) => editor.load(markdown, generation),
  reload: (markdown, generation) => editor.reload(markdown, generation),
  markdown: () => editor.markdown(),
  clipboard: () => editor.clipboard(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  insertText: (text, generation) => editor.insertText(text, generation),
  keyDown: (key, code, meta, ctrl, alt, shift, generation) =>
    editor.keyDown(key, code, meta, ctrl, alt, shift, generation),
  find: (text) => editor.find(text),
  insertPaths: (paths, x, y) => editor.insertPaths(paths, x, y),
  setAccent: (color) =>
    document.documentElement.style.setProperty("--accent", color),
  setTextSize: (px) =>
    document.documentElement.style.setProperty("font-size", `${px}px`),
  setKeymap: (keymap) => editor.setKeymap(keymap),
};

window.addEventListener("error", (event) =>
  postToHost({ type: "error", message: event.message }),
);
window.addEventListener("unhandledrejection", (event) =>
  postToHost({ type: "error", message: String(event.reason) }),
);

postToHost({ type: "ready" });
