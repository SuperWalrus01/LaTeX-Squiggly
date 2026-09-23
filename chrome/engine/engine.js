// The conversion engine and the trigger rules, ported from the Windows build,
// which is itself checked against the Swift engine. chrome/test/conformance.mjs
// replays the same 2,030 fragments against this file, so a difference from the
// Mac app shows up there rather than in somebody's email.
//
// A plain script rather than a module: content scripts cannot import, and the
// same file has to load in the page, the popup and Node.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});
  const T = ns.tables;

  const symbols = new Map(T.entries.map((e) => [e.command, e.glyph]));
  const operators = new Map(Object.entries(T.operators));
  const unsupportedReasons = new Map(Object.entries(T.unsupportedReasons));
  const escapedLiterals = new Map(Object.entries(T.escapedLiterals));
  const symbolReasons = new Map(Object.entries(T.symbolReasons));
  const superscripts = new Map(Object.entries(T.superscripts));
  const subscripts = new Map(Object.entries(T.subscripts));
  const radicals = new Map(Object.entries(T.radicals).map(([k, v]) => [Number(k), v]));
  const vulgarFractions = new Map(Object.entries(T.vulgarFractions));

  // MARK: Characters

  // Counting characters the way Swift does. LaTeX source is ASCII, where a
  // code unit is a character, but the engine's output is not: the
  // double-struck alphabet lives outside the basic plane, so \mathbb{X} is one
  // character and two code units. That decides whether a fraction gets
  // parentheses, and how a refusal names the character it could not convert.
  const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
  const isAscii = (text) => !/[^\x00-\x7F]/.test(text);

  function characters(text) {
    if (isAscii(text)) return [...text];
    return Array.from(segmenter.segment(text), (s) => s.segment);
  }

  const characterCount = (text) => (isAscii(text) ? text.length : characters(text).length);
  const isAsciiLetter = (ch) => /^[A-Za-z]$/.test(ch);
  const isWhitespace = (ch) => /^\s$/.test(ch);

  // MARK: Tokenizer

  const TokenizerReasons = {
    unbalancedBrace: "Unbalanced braces — a `{` was never closed.",
    unexpectedClosingBrace: "Unbalanced braces — a `}` has no matching `{`.",
    danglingBackslash: "The input ends with a lone backslash.",
  };

  class Refusal extends Error {}

  // Longest match: a command name is the longest run of ASCII letters, which is
  // what keeps \int from being read as \in then t. The terminator is kept as an
  // ordinary token rather than swallowed, so "\alpha " keeps its space.
  function tokenize(input) {
    const state = { i: 0 };
    const tokens = scan(input, state, 0);
    // A `}` at depth 0 stops the scan; anything left over is unmatched.
    if (state.i !== input.length) throw new Refusal(TokenizerReasons.unexpectedClosingBrace);
    return tokens;
  }

  function scan(c, state, depth) {
    const output = [];
    while (state.i < c.length) {
      const ch = c[state.i];
      if (ch === "\\") {
        state.i += 1;
        if (state.i >= c.length) throw new Refusal(TokenizerReasons.danglingBackslash);
        if (isAsciiLetter(c[state.i])) {
          let name = "";
          while (state.i < c.length && isAsciiLetter(c[state.i])) name += c[state.i++];
          output.push({ type: "command", name });
        } else {
          output.push({ type: "controlSymbol", symbol: c[state.i] });
          state.i += 1;
        }
      } else if (ch === "{") {
        state.i += 1;
        const inner = scan(c, state, depth + 1);
        if (state.i >= c.length || c[state.i] !== "}") {
          throw new Refusal(TokenizerReasons.unbalancedBrace);
        }
        state.i += 1;
        output.push({ type: "group", inner });
      } else if (ch === "}") {
        // Let the caller consume it; at depth 0 tokenize rejects it.
        return output;
      } else if (ch === "^") {
        output.push({ type: "sup" });
        state.i += 1;
      } else if (ch === "_") {
        output.push({ type: "sub" });
        state.i += 1;
      } else {
        output.push({ type: "character", value: ch });
        state.i += 1;
      }
    }
    if (depth > 0) throw new Refusal(TokenizerReasons.unbalancedBrace);
    return output;
  }

  // MARK: Renderer

  const DIVISION_SLASH = "∕";
  const scriptKinds = {
    sup: { name: "superscript", marker: "^", table: superscripts },
    sub: { name: "subscript", marker: "_", table: subscripts },
  };

  // Replaces the hyphen with U+2212 MINUS SIGN. Only linear maths goes through
  // here, so \text{well-known} keeps its hyphen.
  const mathematical = (text) => text.replaceAll("-", "−");
  const parenthesised = (text) => (characterCount(text) === 1 ? text : "(" + text + ")");

  const containsScript = (tokens) =>
    tokens.some((t) => t.type === "sup" || t.type === "sub" ||
      (t.type === "group" && containsScript(t.inner)));

  // Swift's Int(): an optional sign and ASCII digits, nothing else, and nil
  // when the value does not fit in 64 bits.
  function swiftInt(text) {
    if (!/^[+-]?[0-9]+$/.test(text)) return null;
    const value = BigInt(text);
    if (value > 9223372036854775807n || value < -9223372036854775808n) return null;
    return Number(value);
  }

  class Renderer {
    constructor(tokens) {
      this.tokens = tokens;
      this.index = 0;
      this.text = "";
      this.fallbacks = [];
    }

    static render(tokens) {
      const renderer = new Renderer(tokens);
      renderer.run();
      return renderer;
    }

    append(other) {
      this.text += other.text;
      this.fallbacks.push(...other.fallbacks);
    }

    run() {
      while (this.index < this.tokens.length) {
        const token = this.tokens[this.index++];
        switch (token.type) {
          case "character": this.text += token.value; break;
          case "group": this.append(Renderer.render(token.inner)); break;
          case "sup":
          case "sub": this.applyScript(scriptKinds[token.type]); break;
          case "controlSymbol": this.emitControlSymbol(token.symbol); break;
          case "command": this.emitCommand(token.name); break;
        }
      }
    }

    // The next argument: a braced group's contents or a single token, so
    // \frac12 and \frac{1}{2} behave the same. Whitespace before it is skipped,
    // so \mathbb R works.
    nextUnit() {
      while (this.index < this.tokens.length) {
        const white = this.tokens[this.index];
        if (white.type !== "character" || !isWhitespace(white.value)) break;
        this.index += 1;
      }
      if (this.index >= this.tokens.length) return null;
      const token = this.tokens[this.index++];
      return token.type === "group" ? token.inner : [token];
    }

    applyScript(kind) {
      const unit = this.nextUnit();
      if (unit === null) throw new Refusal(`\`${kind.marker}\` has nothing after it to convert.`);
      if (unit.length === 0) throw new Refusal(`The ${kind.name} is empty.`);
      if (containsScript(unit)) {
        throw new Refusal("Nested superscripts and subscripts have no Unicode form.");
      }
      const inner = Renderer.render(unit);
      for (const character of characters(inner.text)) {
        const mapped = character.length === 1 ? kind.table.get(character) : undefined;
        if (mapped === undefined) {
          throw new Refusal(`There is no Unicode ${kind.name} for “${character}”.`);
        }
        this.text += mapped;
      }
      this.fallbacks.push(...inner.fallbacks);
    }

    emitCommand(name) {
      switch (name) {
        case "frac": case "dfrac": case "tfrac": this.emitFraction(name); return;
        case "sqrt": this.emitRoot(); return;
        case "binom": case "dbinom": case "tbinom": this.emitBinomial(name); return;
        case "text": case "textrm": case "mathrm": case "operatorname":
          this.emitVerbatimGroup(name); return;
        case "mathbb": this.emitBlackboardBold(); return;
        // Delimiter sizing only. The delimiter itself is the next token.
        case "left": case "right": return;
        case "begin": case "end": this.rejectEnvironment(); return;
      }
      if (operators.has(name)) { this.text += operators.get(name); return; }
      if (unsupportedReasons.has(name)) throw new Refusal(unsupportedReasons.get(name));
      if (symbols.has(name)) { this.text += symbols.get(name); return; }
      throw new Refusal(`Unknown command \\${name}.`);
    }

    emitControlSymbol(character) {
      if (escapedLiterals.has(character)) { this.text += escapedLiterals.get(character); return; }
      if (symbolReasons.has(character)) throw new Refusal(symbolReasons.get(character));
      throw new Refusal(`Unknown command \\${character}.`);
    }

    emitFraction(name) {
      const numerator = this.nextUnit();
      const denominator = this.nextUnit();
      if (numerator === null || denominator === null) {
        throw new Refusal(`\\${name} needs two arguments, for example \\${name}{a}{b}.`);
      }
      const top = Renderer.render(numerator);
      const bottom = Renderer.render(denominator);
      if (top.text.length === 0 || bottom.text.length === 0) {
        throw new Refusal(`\\${name} has an empty argument.`);
      }

      // A fraction whose arguments already needed an approximation goes
      // straight to the linear form rather than dressing up a fallback.
      if (top.fallbacks.length === 0 && bottom.fallbacks.length === 0) {
        const exact = vulgarFractions.get(`${top.text}/${bottom.text}`);
        if (exact !== undefined) { this.text += exact; return; }
        if (worthComposing(top.text, bottom.text)) {
          const composed = composedFraction(top.text, bottom.text);
          if (composed !== null) { this.text += composed; return; }
        }
      }

      this.text += mathematical(parenthesised(top.text)) + DIVISION_SLASH +
        mathematical(parenthesised(bottom.text));
      this.fallbacks.push(...top.fallbacks, ...bottom.fallbacks,
        "A fraction cannot be stacked in plain text, so it was written on one line with a slash.");
    }

    emitRoot() {
      let degree = 2;
      let degreeText = "2";

      // Optional [n], recognised only immediately after \sqrt.
      const next = this.tokens[this.index];
      if (next && next.type === "character" && next.value === "[") {
        let scan = this.index + 1;
        const inner = [];
        while (scan < this.tokens.length &&
               !(this.tokens[scan].type === "character" && this.tokens[scan].value === "]")) {
          inner.push(this.tokens[scan]);
          scan += 1;
        }
        if (scan >= this.tokens.length) throw new Refusal("\\sqrt has a `[` that is never closed.");
        this.index = scan + 1;
        degreeText = Renderer.render(inner).text;

        if (degreeText.length === 0) {
          throw new Refusal("\\sqrt has an empty index, for example \\sqrt[3]{8}.");
        }
        const written = swiftInt(degreeText);
        if (written !== null && written < 2) {
          throw new Refusal(`A root needs an index of at least 2, so \\sqrt[${written}] is not one.`);
        }
        degree = written ?? -1;
      }

      const argument = this.nextUnit();
      if (argument === null) throw new Refusal("\\sqrt needs an argument, for example \\sqrt{2}.");
      const radicand = Renderer.render(argument);
      if (radicand.text.length === 0) throw new Refusal("\\sqrt has an empty argument.");
      this.fallbacks.push(...radicand.fallbacks);

      const radical = radicals.get(degree);
      if (radical !== undefined) {
        this.text += radical + mathematical(parenthesised(radicand.text));
        this.fallbacks.push(
          `A radical sign cannot extend over what is under it, so the root was written as ${radical}(…).`);
      } else {
        this.text += mathematical(parenthesised(radicand.text)) + "^(1/" + degreeText + ")";
        this.fallbacks.push(
          `There is no Unicode radical sign for an index of ${degreeText}, so the root was written as a fractional power.`);
      }
    }

    emitBinomial(name) {
      const upper = this.nextUnit();
      const lower = this.nextUnit();
      if (upper === null || lower === null) {
        throw new Refusal(`\\${name} needs two arguments, for example \\${name}{n}{k}.`);
      }
      const n = Renderer.render(upper);
      const k = Renderer.render(lower);
      if (n.text.length === 0 || k.text.length === 0) {
        throw new Refusal(`\\${name} has an empty argument.`);
      }
      this.text += `C(${mathematical(n.text)}, ${mathematical(k.text)})`;
      this.fallbacks.push(...n.fallbacks, ...k.fallbacks,
        "A binomial coefficient cannot be stacked in plain text, so it was written as C(n, k).");
    }

    emitVerbatimGroup(name) {
      const unit = this.nextUnit();
      if (unit === null) throw new Refusal(`\\${name} needs an argument.`);
      this.append(Renderer.render(unit));
    }

    emitBlackboardBold() {
      const unit = this.nextUnit();
      if (unit === null) throw new Refusal("\\mathbb needs a letter, for example \\mathbb{R}.");
      const letter = Renderer.render(unit).text;
      if (characterCount(letter) !== 1 || !symbols.has(letter)) {
        throw new Refusal(`There is no double-struck Unicode letter for “${letter}”.`);
      }
      this.text += symbols.get(letter);
    }

    rejectEnvironment() {
      const unit = this.nextUnit();
      let name = "";
      if (unit !== null) {
        try { name = Renderer.render(unit).text; } catch { name = ""; }
      }
      if (name.length === 0) {
        throw new Refusal(
          "LaTeX environments need two-dimensional layout, which has no inline Unicode form.");
      }
      throw new Refusal(
        `The ${name} environment needs two-dimensional layout, which has no inline Unicode form.`);
    }
  }

  // Whether a composed fraction would still be readable. Digits stay legible at
  // any length; anything else only when both parts are short. Checked per code
  // unit, as the Windows port does, so a lone surrogate is never a number.
  function worthComposing(numerator, denominator) {
    const numeric = (text) => {
      for (let i = 0; i < text.length; i++) if (!/^\p{N}$/u.test(text[i])) return false;
      return true;
    };
    const bothNumeric = numeric(numerator) && numeric(denominator);
    const bothShort = characterCount(numerator) <= 2 && characterCount(denominator) <= 2;
    return bothNumeric || bothShort;
  }

  // A diagonal fraction built from script characters, or null when any
  // character lacks the form it needs.
  function composedFraction(numerator, denominator) {
    let result = "";
    for (let i = 0; i < numerator.length; i++) {
      const raised = superscripts.get(numerator[i]);
      if (raised === undefined) return null;
      result += raised;
    }
    result += T.fractionSlash;
    for (let i = 0; i < denominator.length; i++) {
      const lowered = subscripts.get(denominator[i]);
      if (lowered === undefined) return null;
      result += lowered;
    }
    return result;
  }

  // All or nothing: a half-converted string is never produced.
  function convert(latex) {
    if (latex.length === 0) {
      return { kind: "unsupported", text: null, reason: "There is nothing to convert." };
    }
    try {
      const rendered = Renderer.render(tokenize(latex));
      if (rendered.fallbacks.length === 0) {
        return { kind: "converted", text: rendered.text, reason: null };
      }
      return { kind: "fallback", text: rendered.text, reason: [...new Set(rendered.fallbacks)].join(" ") };
    } catch (error) {
      if (error instanceof Refusal) return { kind: "unsupported", text: null, reason: error.message };
      throw error;
    }
  }

  // MARK: Known commands

  const structural = new Set([
    "frac", "dfrac", "tfrac", "sqrt", "binom", "dbinom", "tbinom",
    "text", "textrm", "mathrm", "operatorname", "mathbb",
    "left", "right", "begin", "end",
  ]);

  function leadingCommandName(candidate) {
    if (candidate[0] !== "\\") return null;
    const match = /^[A-Za-z]+/.exec(candidate.slice(1));
    return match ? match[0] : null;
  }

  const isKnown = (name) =>
    symbols.has(name) || operators.has(name) || unsupportedReasons.has(name) || structural.has(name);

  const isKnownControlSymbol = (ch) => escapedLiterals.has(ch) || symbolReasons.has(ch);

  // True when the candidate opens with a command someone could have meant.
  function looksIntentional(candidate) {
    const name = leadingCommandName(candidate);
    return name !== null && isKnown(name);
  }

  // True when every command is known and the braces balance. Reporting a
  // failure needs this: C:\path\to\file opens with \to, a real command, and
  // must still stay quiet.
  function isWhollyIntentional(candidate) {
    let index = 0;
    let depth = 0;
    let sawCommand = false;
    while (index < candidate.length) {
      const ch = candidate[index];
      if (ch === "\\") {
        index += 1;
        if (index >= candidate.length) return false;
        if (isAsciiLetter(candidate[index])) {
          let name = "";
          while (index < candidate.length && isAsciiLetter(candidate[index])) name += candidate[index++];
          if (!isKnown(name)) return false;
        } else {
          if (!isKnownControlSymbol(candidate[index])) return false;
          index += 1;
        }
        sawCommand = true;
      } else if (ch === "{") {
        depth += 1;
        index += 1;
      } else if (ch === "}") {
        depth -= 1;
        if (depth < 0) return false;
        index += 1;
      } else {
        index += 1;
      }
    }
    return sawCommand && depth === 0;
  }

  // MARK: Trigger detection

  // Longest $...$ span considered, so a stray dollar earlier in the sentence
  // cannot swallow half a line.
  const MAXIMUM_DELIMITED_LENGTH = 48;

  const none = () => ({ kind: "none" });

  // `source` is the exact typed text the replacement removes. The desktop apps
  // only need its length; the extension compares it against the page before
  // touching anything.
  const replace = (source, result, terminator) => ({
    kind: "replace",
    source,
    deleteCount: characterCount(source),
    insert: result.text + terminator,
    notice: result.reason,
  });

  const refuse = (source, reason) => ({ kind: "refuse", source, reason });

  // $x^2$ is something nobody types by accident, where bare x^2 is. A failure
  // here is always reported: the dollars are a statement of intent.
  function mathDelimited(buffer, terminator) {
    if (buffer.length === 0 || buffer[buffer.length - 1] !== "$") return null;
    const beforeClosing = buffer.slice(0, -1);
    const opening = beforeClosing.lastIndexOf("$");
    if (opening < 0) return null;

    const content = beforeClosing.slice(opening + 1);
    if (content.length === 0 ||
        characterCount(content) > MAXIMUM_DELIMITED_LENGTH ||
        !/[\\^_]/.test(content)) {
      return null;
    }
    const result = convert(content);
    if (result.kind === "unsupported") return refuse("$" + content + "$", result.reason);
    return replace("$" + content + "$", result, terminator);
  }

  // Every point a candidate could begin, earliest first, within the run since
  // the last whitespace. Earliest first is what keeps \frac{\alpha}{2} whole.
  function candidateStarts(buffer) {
    let runStart = 0;
    for (let i = buffer.length - 1; i >= 0; i--) {
      if (isWhitespace(buffer[i])) { runStart = i + 1; break; }
    }
    const starts = [];
    for (let i = runStart; i < buffer.length; i++) {
      if (buffer[i] === "\\") starts.push(buffer.slice(i));
    }
    return starts;
  }

  // What to do given the text just typed and the terminator. The terminator is
  // assumed suppressed by the caller, so `insert` carries it back.
  function outcome(buffer, terminator) {
    const delimited = mathDelimited(buffer, terminator);
    if (delimited !== null) return delimited;

    let refusal = null;
    for (const candidate of candidateStarts(buffer)) {
      if (characterCount(candidate) <= 1) continue;
      if (!looksIntentional(candidate)) continue;

      const result = convert(candidate);
      if (result.kind !== "unsupported") return replace(candidate, result, terminator);
      if (refusal === null && isWhollyIntentional(candidate)) {
        refusal = refuse(candidate, result.reason);
      }
    }
    return refusal ?? none();
  }

  ns.engine = { convert, outcome, characters, characterCount };
})();
