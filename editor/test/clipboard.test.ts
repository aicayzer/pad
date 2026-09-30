import { expect, test } from "vitest";
import { editorViewCtx } from "@milkdown/kit/core";
import type { Ctx } from "@milkdown/kit/ctx";
import { AllSelection } from "@milkdown/kit/prose/state";
import { PadEditor } from "../src/editor";

function pasteEvent(text: string, html = ""): ClipboardEvent {
  const event = new Event("paste");
  Object.defineProperty(event, "clipboardData", {
    value: {
      getData: (type: string) =>
        type === "text/plain" ? text : type === "text/html" ? html : "",
    },
  });
  return event as ClipboardEvent;
}

async function withEditor(run: (editor: PadEditor, ctx: Ctx) => void) {
  const root = document.createElement("div");
  document.body.append(root);
  const editor = await PadEditor.mount(root, {
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  });
  try {
    run(editor, (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx);
  } finally {
    root.remove();
  }
}

test("selection copy exports visible punctuation and spaces instead of Markdown escapes", async () => {
  await withEditor((editor, ctx) => {
    editor.load("", 1);
    const view = ctx.get(editorViewCtx);
    const { schema } = view.state;
    const paragraphs = [
      "it;s removed? & other chars ",
      "literal &#x20; and &amp;",
      "**literal stars**; <text>",
    ];
    const doc = schema.node(
      "doc",
      null,
      paragraphs.map((text) =>
        schema.node("paragraph", null, schema.text(text)),
      ),
    );
    view.dispatch(
      view.state.tr.replaceWith(0, view.state.doc.content.size, doc.content),
    );
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)));
    const slice = view.state.selection.content();
    let copied = "";
    view.someProp("clipboardTextSerializer", (serialize) => {
      copied = serialize(slice, view);
      return true;
    });
    expect(copied).toBe(paragraphs.join("\n\n"));
    const selection = view.state.selection.toJSON();
    const content = editor.clipboard();
    expect(content.text).toBe(copied);
    const dom = document.createElement("div");
    dom.innerHTML = content.html;
    expect(
      Array.from(dom.querySelectorAll("p"), (node) => node.textContent),
    ).toEqual(paragraphs);
    expect(view.state.selection.toJSON()).toEqual(selection);
  });
});

test("formatted copy carries semantic HTML and readable text without source markers", async () => {
  await withEditor((editor, ctx) => {
    editor.load(
      "# Heading\n\n**Bold** and *italic* [link](https://example.com).\n\n- First\n- Second\n\n```txt\n& literal &#x20;\n```",
      1,
    );
    const copied = editor.clipboard();
    expect(copied.text).toBe(
      "Heading\n\nBold and italic link.\n\n- First\n- Second\n\n& literal &#x20;",
    );
    expect(copied.html).toContain("<strong>Bold</strong>");
    expect(copied.html).toContain("<em>italic</em>");
    expect(copied.html).toContain('href="https://example.com"');
    expect(editor.markdown()).toBe(null);
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)));
    view.pasteHTML(copied.html, pasteEvent(copied.text, copied.html));
    expect(editor.clipboard().text).toBe(copied.text);
  });
});

test("Markdown paste formats ordinary text and decodes source entities exactly once", async () => {
  await withEditor((editor, ctx) => {
    editor.load("", 1);
    const view = ctx.get(editorViewCtx);
    const text =
      "**it;s removed?** & more\n\nA&#x20;B &amp; C; `literal &#x20;`";
    view.pasteText(text, pasteEvent(text));
    expect(editor.clipboard().text).toBe(
      "it;s removed? & more\n\nA B & C; literal &#x20;",
    );
    expect(editor.clipboard().html).toContain("<strong>it;s removed?</strong>");
  });
});

test("copy retains hard breaks, authored blank paragraphs, and literal unsupported content", async () => {
  await withEditor((editor, ctx) => {
    editor.load("", 1);
    const view = ctx.get(editorViewCtx);
    const { schema } = view.state;
    const hardbreak = schema.nodes.hardbreak ?? schema.nodes.hard_break;
    const content = [
      schema.node("paragraph", null, [
        schema.text("one"),
        hardbreak!.create(),
        schema.text("two"),
      ]),
      schema.node("paragraph"),
      schema.node(
        "literal_markdown",
        null,
        schema.text("<div>&amp; &#x20;</div>"),
      ),
      schema.node("paragraph"),
    ];
    view.dispatch(
      view.state.tr.replaceWith(0, view.state.doc.content.size, content),
    );
    const copied = editor.clipboard();
    expect(copied.text).toBe("one\ntwo\n\n\n\n<div>&amp; &#x20;</div>\n\n");
    const container = document.createElement("div");
    container.innerHTML = copied.html;
    expect(container.querySelector("pre")?.textContent).toBe(
      "<div>&amp; &#x20;</div>",
    );
  });
});

test("plain clipboard keeps nested list hierarchy and continuation paragraphs", async () => {
  await withEditor((editor) => {
    editor.load(
      "- Parent\n  - Child\n    3. Nested three\n    4. Nested four\n\n  Continuation paragraph\n\n- Other\n\n9. Nine\n   - Nested bullet\n10. Ten",
      1,
    );
    expect(editor.clipboard().text).toBe(
      "- Parent\n  - Child\n    3. Nested three\n    4. Nested four\n\n  Continuation paragraph\n- Other\n\n9. Nine\n   - Nested bullet\n10. Ten",
    );
  });
});

test("soft line breaks remain visible without converting or dirtying source", async () => {
  await withEditor((editor, ctx) => {
    const source = "sdfsdf\n\nsadfsdfasdf\n\nasdfasdf\nsadfasdf";
    editor.load(source, 1);
    const view = ctx.get(editorViewCtx);
    expect(view.dom.querySelector('br[data-type="softbreak"]')).not.toBeNull();
    expect(editor.clipboard().text).toBe(source);
    expect(editor.markdown()).toBe(null);
    const copied = editor.clipboard();
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)));
    view.pasteHTML(copied.html, pasteEvent(copied.text, copied.html));
    expect(editor.markdown()).toBe(null);
    view.dispatch(
      view.state.tr.insertText("!", view.state.doc.content.size - 1),
    );
    const saved = editor.markdown()!;
    expect(saved).toBe(source + "!\n");
    editor.load(saved, 2);
    expect(view.dom.querySelector('br[data-type="softbreak"]')).not.toBeNull();
    expect(editor.clipboard().text).toBe(source + "!");
    expect(editor.markdown()).toBe(null);
  });
});
