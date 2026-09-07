using System.Text;

namespace LaTeXSquiggly.Core.Engine;

/// <summary>
/// Converts a LaTeX fragment to inline Unicode.
///
/// Accepts a whole fragment, not just a single command: literal text passes
/// through untouched, so Convert("x^2 + \\alpha") yields "x² + α".
///
/// The result is all-or-nothing. If any part of the input has no faithful
/// Unicode form the whole call returns Unsupported: a half-converted string is
/// never produced.
/// </summary>
public static class Converter
{
    public static ConversionResult Convert(string latex)
    {
        if (latex.Length == 0)
        {
            return ConversionResult.Unsupported("There is nothing to convert.");
        }
        try
        {
            var rendered = Renderer.Render(Tokenizer.Tokenize(latex));
            if (rendered.Fallbacks.Count == 0)
            {
                return ConversionResult.Converted(rendered.Text.ToString());
            }
            return ConversionResult.Fallback(
                rendered.Text.ToString(), string.Join(" ", Deduplicated(rendered.Fallbacks)));
        }
        catch (UnsupportedInputException error)
        {
            return ConversionResult.Unsupported(error.Message);
        }
        catch (TokenizerException error)
        {
            return ConversionResult.Unsupported(error.Message);
        }
    }

    private static List<string> Deduplicated(IEnumerable<string> items)
    {
        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var item in items)
        {
            if (seen.Add(item)) result.Add(item);
        }
        return result;
    }
}

internal sealed class UnsupportedInputException : Exception
{
    public UnsupportedInputException(string reason) : base(reason) { }
}

internal sealed class Rendered
{
    public StringBuilder Text { get; } = new();
    public List<string> Fallbacks { get; } = new();

    public void Append(Rendered other)
    {
        Text.Append(other.Text);
        Fallbacks.AddRange(other.Fallbacks);
    }
}

internal enum ScriptKind { Sup, Sub }

internal static class ScriptKindExtensions
{
    public static string Name(this ScriptKind kind) =>
        kind == ScriptKind.Sup ? "superscript" : "subscript";

    public static char Marker(this ScriptKind kind) => kind == ScriptKind.Sup ? '^' : '_';

    public static IReadOnlyDictionary<char, char> Table(this ScriptKind kind) =>
        kind == ScriptKind.Sup ? ScriptTables.Superscripts : ScriptTables.Subscripts;
}

internal sealed class Renderer
{
    /// <summary>U+2215, the division operator, rather than the ASCII solidus.</summary>
    private const char DivisionSlash = '∕';

    private readonly IReadOnlyList<Token> _tokens;
    private int _index;
    private readonly Rendered _out = new();

    private Renderer(IReadOnlyList<Token> tokens) => _tokens = tokens;

    public static Rendered Render(IReadOnlyList<Token> tokens)
    {
        var renderer = new Renderer(tokens);
        renderer.Run();
        return renderer._out;
    }

    private void Run()
    {
        while (_index < _tokens.Count)
        {
            var token = _tokens[_index];
            _index += 1;
            switch (token)
            {
                case Token.Character character: _out.Text.Append(character.Value); break;
                case Token.Group group: _out.Append(Render(group.Inner)); break;
                case Token.Sup: ApplyScript(ScriptKind.Sup); break;
                case Token.Sub: ApplyScript(ScriptKind.Sub); break;
                case Token.ControlSymbol symbol: EmitControlSymbol(symbol.Symbol); break;
                case Token.Command command: EmitCommand(command.Name); break;
            }
        }
    }

    /// <summary>
    /// The next argument: a braced group's contents, or a single token, so
    /// <c>\frac12</c> and <c>\frac{1}{2}</c> behave the same, as in LaTeX.
    ///
    /// Whitespace before an argument is skipped, so <c>\mathbb R</c> works. This
    /// does not contradict the tokenizer's rule that a command's terminator is
    /// preserved: that rule is about symbol commands, which take no argument and
    /// so never reach here.
    /// </summary>
    private IReadOnlyList<Token>? NextUnit()
    {
        while (_index < _tokens.Count
               && _tokens[_index] is Token.Character white
               && char.IsWhiteSpace(white.Value))
        {
            _index += 1;
        }
        if (_index >= _tokens.Count) return null;

        var token = _tokens[_index];
        _index += 1;
        if (token is Token.Group group) return group.Inner;
        return new[] { token };
    }

    // MARK: Scripts

    private void ApplyScript(ScriptKind kind)
    {
        var unit = NextUnit();
        if (unit is null)
        {
            throw new UnsupportedInputException(
                $"`{kind.Marker()}` has nothing after it to convert.");
        }
        if (unit.Count == 0)
        {
            throw new UnsupportedInputException($"The {kind.Name()} is empty.");
        }
        if (ContainsScript(unit))
        {
            throw new UnsupportedInputException(
                "Nested superscripts and subscripts have no Unicode form.");
        }

        var inner = Render(unit);
        // Whole characters, not UTF-16 halves: a double-struck letter is one
        // character to the user and to Swift, so a refusal has to name it as one.
        foreach (var character in Core.Text.Characters(inner.Text.ToString()))
        {
            if (character.Length != 1 || !kind.Table().TryGetValue(character[0], out var mapped))
            {
                throw new UnsupportedInputException(
                    $"There is no Unicode {kind.Name()} for “{character}”.");
            }
            _out.Text.Append(mapped);
        }
        _out.Fallbacks.AddRange(inner.Fallbacks);
    }

    // MARK: Commands

    private void EmitCommand(string name)
    {
        switch (name)
        {
            case "frac" or "dfrac" or "tfrac": EmitFraction(name); return;
            case "sqrt": EmitRoot(); return;
            case "binom" or "dbinom" or "tbinom": EmitBinomial(name); return;
            case "text" or "textrm" or "mathrm" or "operatorname": EmitVerbatimGroup(name); return;
            case "mathbb": EmitBlackboardBold(); return;
            // Delimiter sizing only. The delimiter itself is the next token.
            case "left" or "right": return;
            case "begin" or "end": RejectEnvironment(); return;
        }

        if (TextOperators.Operators.TryGetValue(name, out var operatorText))
        {
            _out.Text.Append(operatorText);
            return;
        }
        if (UnsupportedCommands.Reasons.TryGetValue(name, out var reason))
        {
            throw new UnsupportedInputException(reason);
        }
        if (SymbolTable.Symbols.TryGetValue(name, out var symbol))
        {
            _out.Text.Append(symbol);
            return;
        }
        throw new UnsupportedInputException($"Unknown command \\{name}.");
    }

    private void EmitControlSymbol(char character)
    {
        if (UnsupportedCommands.EscapedLiterals.TryGetValue(character, out var literal))
        {
            _out.Text.Append(literal);
            return;
        }
        if (UnsupportedCommands.SymbolReasons.TryGetValue(character, out var reason))
        {
            throw new UnsupportedInputException(reason);
        }
        throw new UnsupportedInputException($"Unknown command \\{character}.");
    }

    // MARK: Fallback constructions

    private void EmitFraction(string name)
    {
        var numerator = NextUnit();
        var denominator = NextUnit();
        if (numerator is null || denominator is null)
        {
            throw new UnsupportedInputException(
                $"\\{name} needs two arguments, for example \\{name}{{a}}{{b}}.");
        }
        var top = Render(numerator);
        var bottom = Render(denominator);
        var topText = top.Text.ToString();
        var bottomText = bottom.Text.ToString();
        if (topText.Length == 0 || bottomText.Length == 0)
        {
            throw new UnsupportedInputException($"\\{name} has an empty argument.");
        }

        // A fraction whose own arguments already needed an approximation cannot
        // be represented exactly, so those go straight to the linear form rather
        // than dressing up a fallback as a real fraction.
        if (top.Fallbacks.Count == 0 && bottom.Fallbacks.Count == 0)
        {
            // Best: a single precomposed character.
            if (ScriptTables.VulgarFractions.TryGetValue($"{topText}/{bottomText}", out var exact))
            {
                _out.Text.Append(exact);
                return;
            }
            // Next best: superscript numerator, fraction slash, subscript
            // denominator, which composes anything whose parts both have script
            // forms, so 10/17 works though no single character for it exists.
            if (WorthComposing(topText, bottomText))
            {
                var composed = ComposedFraction(topText, bottomText);
                if (composed is not null)
                {
                    _out.Text.Append(composed);
                    return;
                }
            }
        }

        _out.Text.Append(Mathematical(Parenthesised(topText)))
                 .Append(DivisionSlash)
                 .Append(Mathematical(Parenthesised(bottomText)));
        _out.Fallbacks.AddRange(top.Fallbacks);
        _out.Fallbacks.AddRange(bottom.Fallbacks);
        _out.Fallbacks.Add(
            "A fraction cannot be stacked in plain text, so it was written on one line with a slash.");
    }

    /// <summary>
    /// Whether a composed fraction would still be readable. Script characters
    /// are small, and superscript x against subscript x is close to
    /// indistinguishable at text size. Digits stay legible at any length.
    /// </summary>
    private static bool WorthComposing(string numerator, string denominator)
    {
        var bothNumeric = numerator.All(char.IsNumber) && denominator.All(char.IsNumber);
        var bothShort = Core.Text.CharacterCount(numerator) <= 2
                        && Core.Text.CharacterCount(denominator) <= 2;
        return bothNumeric || bothShort;
    }

    /// <summary>
    /// Builds a diagonal fraction out of existing script characters. Null when
    /// any character lacks the form it needs: the subscript alphabet is missing
    /// b c d f g q w y z, so <c>\frac{a}{b}</c> falls back to a/b instead.
    /// </summary>
    private static string? ComposedFraction(string numerator, string denominator)
    {
        var result = new StringBuilder();
        foreach (var character in numerator)
        {
            if (!ScriptTables.Superscripts.TryGetValue(character, out var raised)) return null;
            result.Append(raised);
        }
        result.Append(ScriptTables.FractionSlash);
        foreach (var character in denominator)
        {
            if (!ScriptTables.Subscripts.TryGetValue(character, out var lowered)) return null;
            result.Append(lowered);
        }
        return result.ToString();
    }

    private void EmitRoot()
    {
        var degree = 2;
        var degreeText = "2";

        // Optional [n]. `[` and `]` are ordinary characters everywhere else, so
        // the bracket group is only recognised here, immediately after \sqrt.
        if (_index < _tokens.Count
            && _tokens[_index] is Token.Character { Value: '[' })
        {
            var scan = _index + 1;
            var inner = new List<Token>();
            while (scan < _tokens.Count && _tokens[scan] is not Token.Character { Value: ']' })
            {
                inner.Add(_tokens[scan]);
                scan += 1;
            }
            if (scan >= _tokens.Count)
            {
                throw new UnsupportedInputException("\\sqrt has a `[` that is never closed.");
            }
            _index = scan + 1;
            degreeText = Render(inner).Text.ToString();

            // An index that is missing or not a root produced honest-looking
            // nonsense: \sqrt[]{8} came out as 8^(1/) and \sqrt[0]{8} as
            // 8^(1/0). A letter index is fine and common, \sqrt[n]{x} reads
            // perfectly well as a fractional power; only a number below two is
            // not a root at all.
            if (degreeText.Length == 0)
            {
                throw new UnsupportedInputException(
                    "\\sqrt has an empty index, for example \\sqrt[3]{8}.");
            }
            if (int.TryParse(degreeText, out var written) && written < 2)
            {
                throw new UnsupportedInputException(
                    $"A root needs an index of at least 2, so \\sqrt[{written}] is not one.");
            }
            degree = int.TryParse(degreeText, out var parsed) ? parsed : -1;
        }

        var argument = NextUnit();
        if (argument is null)
        {
            throw new UnsupportedInputException("\\sqrt needs an argument, for example \\sqrt{2}.");
        }
        var radicand = Render(argument);
        var radicandText = radicand.Text.ToString();
        if (radicandText.Length == 0)
        {
            throw new UnsupportedInputException("\\sqrt has an empty argument.");
        }
        _out.Fallbacks.AddRange(radicand.Fallbacks);

        if (ScriptTables.Radicals.TryGetValue(degree, out var radical))
        {
            _out.Text.Append(radical).Append(Mathematical(Parenthesised(radicandText)));
            _out.Fallbacks.Add(
                $"A radical sign cannot extend over what is under it, so the root was written as {radical}(…).");
        }
        else
        {
            _out.Text.Append(Mathematical(Parenthesised(radicandText)))
                     .Append("^(1/").Append(degreeText).Append(')');
            _out.Fallbacks.Add(
                $"There is no Unicode radical sign for an index of {degreeText}, so the root was written as a fractional power.");
        }
    }

    private void EmitBinomial(string name)
    {
        var upper = NextUnit();
        var lower = NextUnit();
        if (upper is null || lower is null)
        {
            throw new UnsupportedInputException(
                $"\\{name} needs two arguments, for example \\{name}{{n}}{{k}}.");
        }
        var n = Render(upper);
        var k = Render(lower);
        var nText = n.Text.ToString();
        var kText = k.Text.ToString();
        if (nText.Length == 0 || kText.Length == 0)
        {
            throw new UnsupportedInputException($"\\{name} has an empty argument.");
        }
        _out.Text.Append($"C({Mathematical(nText)}, {Mathematical(kText)})");
        _out.Fallbacks.AddRange(n.Fallbacks);
        _out.Fallbacks.AddRange(k.Fallbacks);
        _out.Fallbacks.Add(
            "A binomial coefficient cannot be stacked in plain text, so it was written as C(n, k).");
    }

    // MARK: Passthrough constructions

    private void EmitVerbatimGroup(string name)
    {
        var unit = NextUnit();
        if (unit is null)
        {
            throw new UnsupportedInputException($"\\{name} needs an argument.");
        }
        _out.Append(Render(unit));
    }

    private void EmitBlackboardBold()
    {
        var unit = NextUnit();
        if (unit is null)
        {
            throw new UnsupportedInputException(
                "\\mathbb needs a letter, for example \\mathbb{R}.");
        }
        var letter = Render(unit).Text.ToString();
        if (Core.Text.CharacterCount(letter) != 1
            || !SymbolTable.Symbols.TryGetValue(letter, out var symbol))
        {
            throw new UnsupportedInputException(
                $"There is no double-struck Unicode letter for “{letter}”.");
        }
        _out.Text.Append(symbol);
    }

    private void RejectEnvironment()
    {
        var unit = NextUnit();
        string name = "";
        if (unit is not null)
        {
            try { name = Render(unit).Text.ToString(); }
            catch (Exception) { name = ""; }
        }
        if (name.Length == 0)
        {
            throw new UnsupportedInputException(
                "LaTeX environments need two-dimensional layout, which has no inline Unicode form.");
        }
        throw new UnsupportedInputException(
            $"The {name} environment needs two-dimensional layout, which has no inline Unicode form.");
    }

    // MARK: Helpers

    /// <summary>
    /// Replaces the ASCII hyphen with U+2212 MINUS SIGN. A hyphen is not a
    /// minus: it is shorter, sits lower, and reads as a word break. Only linear
    /// maths goes through here, so <c>\text{}</c> keeps its hyphens and
    /// "well-known" is not mangled.
    /// </summary>
    private static string Mathematical(string text) => text.Replace('-', '−');

    /// <summary>
    /// Wraps in parentheses unless it is a single character, so
    /// <c>\frac{1}{2}</c> gives ½ while <c>\frac{x+1}{y-2}</c> gives (x+1)∕(y−2).
    /// </summary>
    private static string Parenthesised(string text) =>
        Core.Text.CharacterCount(text) == 1 ? text : "(" + text + ")";

    private static bool ContainsScript(IReadOnlyList<Token> tokens) =>
        tokens.Any(token => token switch
        {
            Token.Sup or Token.Sub => true,
            Token.Group group => ContainsScript(group.Inner),
            _ => false,
        });
}
