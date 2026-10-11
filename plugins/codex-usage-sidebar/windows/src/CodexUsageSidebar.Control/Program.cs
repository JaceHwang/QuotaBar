using CodexUsageSidebar.Windows;

var localState = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexUsageSidebar", "runtime-state.json");
var hostExecutable = Path.Combine(AppContext.BaseDirectory, "CodexUsageSidebar.Windows.exe");
if (args.Length == 1 && string.Equals(args[0], "status", StringComparison.OrdinalIgnoreCase))
{
    var state = await RuntimeStateReader.LoadAsync(localState, CancellationToken.None);
    var process = RuntimeProcessReader.Find(hostExecutable);
    Console.WriteLine(WindowsControlCommands.Status(process?.CurrentOutcome(state), runtimeRunning: process is not null));
    return 0;
}

if (args.Length != 2 || !string.Equals(args[0], "diagnostic", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("Usage: CodexUsageSidebar.Control status | diagnostic <absolute-output.zip>");
    return 64;
}

if (!Path.IsPathFullyQualified(args[1]) || !string.Equals(Path.GetExtension(args[1]), ".zip", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine("The diagnostic output path must be an absolute .zip path.");
    return 64;
}
var outputPath = Path.GetFullPath(args[1]);

try
{
    var probe = new WindowsDiagnosticProbe(new Win32CodexWindowLocator());
    var report = await probe.CaptureAsync(includeText: false, CancellationToken.None);
    var state = await RuntimeStateReader.LoadAsync(localState, CancellationToken.None);
    var process = RuntimeProcessReader.Find(hostExecutable);
    await WindowsDiagnosticExporter.ExportAsync(outputPath, report, process?.CurrentOutcome(state), CancellationToken.None);
    Console.WriteLine(outputPath);
    return 0;
}
catch (Exception error)
{
    Console.Error.WriteLine(error.Message);
    return 70;
}
