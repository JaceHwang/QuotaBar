using System.Text.Json;
using QuotaBar.Core;

var tests = new (string Name, Action Run)[] {
    ("legacy flag migration preserves unrelated configuration", () => {
        var dir=Path.Combine(Path.GetTempPath(),"quotabar-legacy-"+Guid.NewGuid()); Directory.CreateDirectory(dir);
        try {
            var path=Path.Combine(dir,"config.toml");
            var text="""
                [plugins."codex-usage-sidebar@codex-usage-sidebar"]
                enabled = true # keep comment
                [plugins."other"]
                enabled = true
                """.Replace("\n","\r\n")+"\r\n";
            File.WriteAllText(path,text); var flag=new LegacyPluginFlag(path); Check(flag.Read()==true,"known legacy enabled"); flag.Set(false);
            Check(File.ReadAllText(path)==text.Replace("enabled = true #","enabled = false #"),"only known flag modified"); flag.Set(true); Check(File.ReadAllText(path)==text,"exact logical restore");
        } finally { Directory.Delete(dir,true); }
    }),
    ("tray mouse-down and native click form one dismissal", () => {
        var gate=new TrayClickGate(); gate.BeginMouseDown(); gate.OutsideDismissed();
        Check(gate.SuppressTrayClick(),"native click does not reopen outside-dismissed card");
        Check(!gate.SuppressTrayClick(),"suppression consumed once");
        gate.BeginMouseDown(); gate.OutsideDismissed(); gate.BeginMouseDown();
        Check(!gate.SuppressTrayClick(),"new mouse press can reopen tray detail");
    }),
    ("malformed token cycle dates degrade without overflow", () => {
        var primary=new QuotaWindow(0,100,DateTimeOffset.UnixEpoch,int.MaxValue);
        var quota=new QuotaSnapshot(primary,null,null,null,null,DateTimeOffset.UtcNow);
        Throws(()=>TokenWindow.Days(new TokenUsage([],null,null,null,null,null),quota,DateTimeOffset.UtcNow));
    }),
    ("shared quota response and Bank", () => {
        var q = QuotaDecoder.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts/rate-limits/read-response.json")));
        Check(q.Primary.RemainingPercent == 76 && q.Secondary?.RemainingPercent == 98, "remaining quota");
        Check(q.Bank?.AvailableCount == 2 && q.Bank.Credits?.Count == 2, "bank details");
    }),
    ("absent and invalid primary are unavailable", () => {
        Throws(() => QuotaDecoder.Decode("{\"result\":{\"rateLimits\":{\"primary\":{\"usedPercent\":false,\"resetsAt\":100}}}}"));
        Throws(() => QuotaDecoder.Decode("{\"result\":{\"rateLimits\":{}}}"));
    }),
    ("notification preserves supplementary Bank", () => {
        var old = QuotaDecoder.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts/rate-limits/read-response.json")));
        var updated = QuotaDecoder.Decode(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "contracts/rate-limits/updated-notification.json")), notification: true);
        Check(updated.MergeSupplementary(old).Bank?.AvailableCount == 2, "bank remains");
    }),
    ("click suppression and independent lock", () => {
        var state = new DetailInteractionState(); state.UpdatePointer(true);
        Check(state.ShouldShow, "hover"); state.TogglePinned(true); state.TogglePinned(true);
        Check(!state.ShouldShow, "second click stays dismissed"); state.UpdatePointer(false); state.UpdatePointer(true);
        Check(state.ShouldShow, "hover restores after exit"); state.ToggleLocked(true); state.DismissOutside();
        Check(state.ShouldShow, "outside does not unlock"); state.Reset(); Check(!state.ShouldShow, "close clears lock");
    }),
    ("refresh timeout and bounded backoff", () => {
        var now = DateTimeOffset.Parse("2026-10-12T00:00:00Z"); var s = new RefreshState();
        s.Received(now); Check(!s.ShouldRefresh(now.AddSeconds(59)) && s.ShouldRefresh(now.AddSeconds(60)), "60 second interval");
        for (var i=0;i<8;i++) s.Error("account/rateLimits/read", "network", now);
        Check(!s.ShouldRefresh(now.AddSeconds(299)) && s.ShouldRefresh(now.AddSeconds(300)), "300 cap");
        s.Error("account/rateLimits/read", "401", now); Check(s.Phase==Phase.NeedsLogin && !s.ShouldRefresh(now.AddHours(1)), "authentication stops polling");
    }),
    ("settings survive close and reject corrupt positions", () => {
        var dir = Path.Combine(Path.GetTempPath(), "quotabar-test-"+Guid.NewGuid()); Directory.CreateDirectory(dir);
        try {
            var store = new PreferencesStore(Path.Combine(dir,"preferences.json")); var p = store.Load();
            Check(p.FloatingEnabled && p.ShowsQuotaInformation, "independent defaults");
            store.Save(p with { FloatingEnabled=false, FloatingX=-500, FloatingY=80 });
            var restored=store.Load(); Check(!restored.FloatingEnabled && restored.ShowsQuotaInformation && restored.FloatingX==-500, "persisted hidden and negative position");
            File.WriteAllText(store.Path, "broken json"); Check(store.Load().FloatingEnabled, "corrupt settings fallback");
        } finally { Directory.Delete(dir,true); }
    }),
    ("token values must be integral and nonnegative", () => {
        var t=TokenDecoder.Decode("{\"result\":{\"dailyUsageBuckets\":[{\"startDate\":\"2026-10-12\",\"tokens\":42}],\"summary\":{\"lifetimeTokens\":42}}}");
        Check(t.Days.Count==1 && t.Days[0].Tokens==42, "tokens available");
        Throws(()=>TokenDecoder.Decode("{\"result\":{\"dailyUsageBuckets\":[{\"startDate\":\"2026-10-12\",\"tokens\":-1}]}}"));
    })
};
var failed=0;
foreach(var test in tests) {
    try { test.Run(); Console.WriteLine("PASS "+test.Name); }
    catch(Exception e) { failed++; Console.Error.WriteLine("FAIL "+test.Name+": "+e.Message); }
}
Console.WriteLine($"{tests.Length-failed}/{tests.Length} behavioral tests passed");
try { await ProtocolTests.Run(); Console.WriteLine("PASS runtime protocol lifecycle"); }
catch(Exception e) { failed++; Console.Error.WriteLine("FAIL runtime protocol lifecycle: "+e.Message); }
try { await AccountRegressionTests.Run(); }
catch(Exception e) { failed++; Console.Error.WriteLine("FAIL account regressions: "+e.Message); }
try { InstallerTests.Run(); Console.WriteLine("PASS install, upgrade, rollback, failure recovery and uninstall"); }
catch(Exception e) { failed++; Console.Error.WriteLine("FAIL install transaction: "+e.Message); }
if(Environment.GetEnvironmentVariable("QUOTABAR_TEST_RUNTIME") is string executable) {
    try { await RuntimeIntegrationTests.Run(executable); }
    catch(Exception e) { failed++; Console.Error.WriteLine("FAIL official runtime integration: "+e.Message); }
}
return failed==0 ? 0 : 1;
static void Check(bool value,string message) { if(!value) throw new Exception(message); }
static void Throws(Action run) { try { run(); } catch(FormatException) { return; } throw new Exception("Expected invalid-data rejection"); }
