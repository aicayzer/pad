import { expect, test } from "vitest";
import { editorViewCtx } from "@milkdown/kit/core";
import type { Ctx } from "@milkdown/kit/ctx";
import { PadEditor } from "../src/editor";
import { roundTrip, withEditor } from "./harness";
import { serialize } from "../src/dialect";

const literals = [
  "<section>Hello **there**</section>",
  "![Picture](https://example.com/picture.png)",
  '[reference][id]\n\n[id]: https://example.com "Title"',
  "| Name | Value |\n| --- | --- |\n| One | Two |",
  "Footnote[^one]\n\n[^one]: Original footnote",
  "---\ntitle: Private draft\n---",
];
for (const raw of literals) {
  test(`unsupported content survives adjacent editing: ${raw.split("\n")[0]}`, async () => {
    const input = `${raw}\n\nOrdinary text\n`;
    const result = await withEditor(input, (editor) => {
      const view = editor.ctx.get(editorViewCtx);
      const end = view.state.doc.content.size - 1;
      view.dispatch(view.state.tr.insertText(" edited", end));
      expect(view.dom.querySelector("img")).toBeNull();
      return serialize(editor.ctx);
    });
    expect(result).toContain(raw);
    expect(result).toContain("Ordinary text edited");
    expect(await roundTrip(result)).toBe(result);
  });
}

test("noncanonical supported Markdown stays formatted and unchanged until edited", async () => {
  const root = document.createElement("div");
  document.body.append(root);
  const changes: Array<{ markdown: string; generation: number }> = [];
  const editor = await PadEditor.mount(root, {
    changed: (markdown, generation) => changes.push({ markdown, generation }),
    stateChanged() {},
    openLink() {},
    copy() {},
  });
  editor.load("__bold__ and _italic_\n", 4);
  expect(root.querySelector("strong")?.textContent).toBe("bold");
  expect(root.querySelector("em")?.textContent).toBe("italic");
  expect(root.querySelector("textarea")).toBeNull();
  expect(editor.markdown()).toBeNull();
  expect(changes).toEqual([]);
  const ctx = (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx;
  const view = ctx.get(editorViewCtx);
  view.dispatch(
    view.state.tr.insertText(" now", view.state.doc.content.size - 1),
  );
  expect(editor.markdown()).toContain(" now");
  expect(changes.at(-1)?.generation).toBe(4);
  editor.load("Second document\n", 5);
  expect(editor.markdown()).toBeNull();
  expect(changes.at(-1)?.generation).toBe(4);
  view.dispatch(
    view.state.tr.insertText(" changed", view.state.doc.content.size - 1),
  );
  expect(changes.at(-1)?.generation).toBe(5);
  root.remove();
});

test("TOML frontmatter does not swallow body text in the same CommonMark paragraph", async () => {
  const header = '+++\ntitle = "Draft"\n+++';
  const body = "Body immediately after the header";
  const input = `${header}\n${body}\n\nLater paragraph\n`;
  const result = await withEditor(input, (editor) => {
    const view = editor.ctx.get(editorViewCtx);
    expect(view.dom.textContent).toContain(body);
    view.dispatch(
      view.state.tr.insertText(" edited", view.state.doc.content.size - 1),
    );
    return serialize(editor.ctx);
  });
  expect(result).toContain(header);
  expect(result).toContain(body);
  expect(result).toContain("Later paragraph edited");
  expect(await roundTrip(result)).toBe(result);
});

test("frontmatter requires matching opening and closing delimiters", async () => {
  await withEditor("---\ntitle: Draft\n+++\n\nBody\n", (editor) => {
    const view = editor.ctx.get(editorViewCtx);
    expect(view.dom.querySelector(".literal-markdown")).toBeNull();
    expect(view.dom.textContent).toContain("title: Draft");
    expect(view.dom.textContent).toContain("Body");
  });
});

for (const marker of ["<br />", "<br>", "<br >", "<br/>"]) {
  test(`standalone ${marker} is editable spacing, not literal HTML`, async () => {
    const source = `One\n\n${marker}\n\nTwo\n`;
    await withEditor(source, (editor) => {
      const view = editor.ctx.get(editorViewCtx);
      expect(view.state.doc.childCount).toBe(3);
      expect(view.state.doc.child(1).type.name).toBe("paragraph");
      expect(view.state.doc.child(1).content.size).toBe(0);
      expect(view.dom.querySelector(".literal-markdown")).toBeNull();
    });
  });
}
for (const raw of [
  "Before <br /> after",
  '<br class="custom" />',
  "<br />\n<script>alert(1)</script>",
]) {
  test(`other HTML remains literal: ${raw}`, async () => {
    await withEditor(raw + "\n", (editor) => {
      const view = editor.ctx.get(editorViewCtx);
      expect(view.dom.querySelector(".literal-markdown")?.textContent).toBe(
        raw,
      );
      expect(serialize(editor.ctx)).toContain(raw);
    });
  });
}
for (const source of [
  "<br />\n\nText\n",
  "Text\n\n<br />\n",
  "Text\n\n<br />\n\n<br />\n",
  "<br />\n\n<br />\n",
  "One\n\n<br />\n\n<br />\n\nTwo\n",
  "> One\n>\n> <br />\n>\n> Two\n",
  "- One\n\n  <br />\n\n  Two\n",
]) {
  test(`spacer paragraphs round-trip: ${JSON.stringify(source)}`, async () => {
    const once = await roundTrip(source);
    expect(once).toBe(source);
    expect(await roundTrip(once)).toBe(source);
  });
}
