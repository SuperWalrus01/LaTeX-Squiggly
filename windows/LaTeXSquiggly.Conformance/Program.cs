using System.Text;
using System.Text.Json;
using LaTeXSquiggly.Core.Engine;
using LaTeXSquiggly.Core.Input;

// Replays every fragment the Swift engine was asked about and checks that this
// port answered identically: same text, same reason, same delete count, same
// decision to stay silent.
//
// This runs on any machine, which is the point. The Windows app cannot be built
// or run on a Mac, so without this the port would be shipped on faith.

// Next to the binary when published, next to the source when run from a build
// script whose working directory is the repository root.
// Anything beginning with a dash is a switch that leaked through from the
// build command, not a path. Taking it as one produced a confusing "no
// reference found" for a file that was sitting right there.
var given = args.FirstOrDefault(argument => !argument.StartsWith('-'));
var candidates = given is not null
    ? new[] { given }
    : new[]
    {
        "reference.json",
        Path.Combine(AppContext.BaseDirectory, "reference.json"),
        Path.Combine("windows", "LaTeXSquiggly.Conformance", "reference.json"),
    };
var path = candidates.FirstOrDefault(File.Exists);
if (path is null)
{
    Console.Error.WriteLine(
        "no reference.json found; run Tools/generate_conformance_corpus.py");
    return 2;
}

Console.OutputEncoding = Encoding.UTF8;
var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
var records = JsonSerializer.Deserialize<List<Record>>(File.ReadAllText(path), options)!;

var failures = new List<string>();
var checks = 0;

foreach (var record in records)
{
    checks += 1;
    var engine = Converter.Convert(record.Input);
    var expectedEngine = record.Engine;
    var actualEngineKind = engine.Kind switch
    {
        ConversionKind.Converted => "converted",
        ConversionKind.Fallback => "fallback",
        _ => "unsupported",
    };
    if (actualEngineKind != expectedEngine.Kind
        || engine.Text != expectedEngine.Text
        || engine.Reason != expectedEngine.Reason)
    {
        failures.Add(Describe("engine", record.Input,
            $"{expectedEngine.Kind} text={Show(expectedEngine.Text)} reason={Show(expectedEngine.Reason)}",
            $"{actualEngineKind} text={Show(engine.Text)} reason={Show(engine.Reason)}"));
    }

    checks += 1;
    var outcome = TriggerDetector.Outcome(record.Input, ' ');
    var expected = record.Trigger;
    var actualKind = outcome.Kind switch
    {
        TriggerKind.None => "none",
        TriggerKind.Replace => "replace",
        _ => "refuse",
    };
    string expectedText;
    string actualText;
    switch (expected.Kind)
    {
        case "replace":
            expectedText = $"replace delete={expected.DeleteCount} insert={Show(expected.Insert)} notice={Show(expected.Notice)}";
            actualText = outcome.Kind == TriggerKind.Replace
                ? $"replace delete={outcome.Replacement!.DeleteCount} insert={Show(outcome.Replacement.Insert)} notice={Show(outcome.Replacement.Notice)}"
                : actualKind;
            break;
        case "refuse":
            expectedText = $"refuse source={Show(expected.Source)} reason={Show(expected.Reason)}";
            actualText = outcome.Kind == TriggerKind.Refuse
                ? $"refuse source={Show(outcome.Source)} reason={Show(outcome.Reason)}"
                : actualKind;
            break;
        default:
            expectedText = "none";
            actualText = actualKind;
            break;
    }
    if (expectedText != actualText)
    {
        failures.Add(Describe("trigger", record.Input, expectedText, actualText));
    }
}

var (suppressionPassed, suppressionFailures) = LaTeXSquiggly.Conformance.SuppressionChecks.Run();
checks += suppressionPassed + suppressionFailures.Count;
failures.AddRange(suppressionFailures);

if (failures.Count == 0)
{
    // Written next to the reference so Tools/make_site.py can quote these
    // numbers without a .NET SDK to run this with. A count typed into a web
    // page by hand is a count that is wrong by the next release.
    var summary = Path.Combine(Path.GetDirectoryName(path) ?? ".", "result.json");
    File.WriteAllText(summary, JsonSerializer.Serialize(new
    {
        fragments = records.Count,
        engineChecks = records.Count * 2,
        suppressionChecks = suppressionPassed,
        total = checks,
    }, new JsonSerializerOptions { WriteIndented = true }) + "\n");

    Console.WriteLine($"PASS  engine       {records.Count * 2} checks over {records.Count} fragments,");
    Console.WriteLine("                   every answer identical to the Swift engine");
    Console.WriteLine($"PASS  suppression  {suppressionPassed} checks on the Windows rules");
    Console.WriteLine($"      {checks} checks passed.");
    return 0;
}

foreach (var failure in failures.Take(40)) Console.WriteLine(failure);
if (failures.Count > 40) Console.WriteLine($"... and {failures.Count - 40} more");
Console.WriteLine($"FAIL  {failures.Count} of {checks} checks disagree");
return 1;

static string Show(string? text) => text is null ? "(none)" : "[" + text + "]";

static string Describe(string layer, string input, string expected, string actual) =>
    $"  {layer} {Show(input)}\n    swift: {expected}\n    c#   : {actual}";

sealed record Record(string Input, EngineRecord Engine, TriggerRecord Trigger);

sealed record EngineRecord(string Kind, string? Text, string? Reason);

sealed record TriggerRecord(string Kind, int DeleteCount, string? Insert, string? Notice,
                            string? Source, string? Reason);
