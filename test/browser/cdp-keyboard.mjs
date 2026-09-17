// Limited CDP key vocabulary used by the rendered proof. Enter must carry its
// native carriage-return text to generate activation, not just a keydown event.
export function keyEventPayloads(key, modifiers = 0) {
  const definitions = {
    Tab: { code: "Tab", windowsVirtualKeyCode: 9 },
    Enter: { code: "Enter", windowsVirtualKeyCode: 13, text: "\r" },
    Escape: { code: "Escape", windowsVirtualKeyCode: 27 },
    Space: { key: " ", code: "Space", windowsVirtualKeyCode: 32, text: " " },
    " ": { code: "Space", windowsVirtualKeyCode: 32, text: " " },
    a: { code: "KeyA", windowsVirtualKeyCode: 65, text: "a" },
  };
  if (typeof key !== "string" || !Object.hasOwn(definitions, key) || !Number.isInteger(modifiers) || modifiers < 0 || modifiers > 15) {
    throw new Error("Unsupported proof keyboard input");
  }
  const definition = definitions[key];
  const text = modifiers & (1 | 2 | 4) ? "" : definition.text || "";
  const shared = { key: definition.key || key, code: definition.code, modifiers, windowsVirtualKeyCode: definition.windowsVirtualKeyCode };
  return [
    { ...shared, type: text ? "keyDown" : "rawKeyDown", text, unmodifiedText: text },
    { ...shared, type: "keyUp" },
  ];
}
