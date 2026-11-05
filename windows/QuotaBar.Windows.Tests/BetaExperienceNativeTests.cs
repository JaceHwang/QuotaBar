using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using QuotaBar.Core;
using QuotaBar.Windows;

internal static class BetaExperienceNativeTests {
    static IEnumerable<DependencyObject> Tree(DependencyObject node) {
        yield return node;
        for(var i=0;i<VisualTreeHelper.GetChildrenCount(node);i++) foreach(var child in Tree(VisualTreeHelper.GetChild(node,i))) yield return child;
    }
    static void Pump() { var frame=new DispatcherFrame(); Dispatcher.CurrentDispatcher.BeginInvoke(DispatcherPriority.Background,()=>frame.Continue=false); Dispatcher.PushFrame(frame); }
    static void Wait(Task task) { var until=DateTime.UtcNow.AddSeconds(5); while(!task.IsCompleted && DateTime.UtcNow<until) Pump(); if(!task.IsCompleted) throw new Exception("Beta action timed out"); task.GetAwaiter().GetResult(); }
    public static void Run(Application app) {
        var root=Path.Combine(Path.GetTempPath(),"quotabar-beta-native-"+Guid.NewGuid()); Directory.CreateDirectory(root);
        try {
            using var owner=new Coordinator(app,root,new HttpClient(),new BarkTests.Secrets(),new BarkTests.AcceptedTransport());
            owner.Save(new Preferences { Language="zh-CN",AutomaticUpdates=false },false); owner.ShowUpdateSettings(); Pump();
            var window=app.Windows.OfType<SettingsWindow>().Single(w=>w.IsVisible); window.ShowAbout(); Pump();
            var toggle=Tree(window).OfType<CheckBox>().Single(c=>Equals(c.Tag,"settings.betaExperience"));
            if(toggle.IsChecked!=false) throw new Exception("Beta must start disabled");
            var steps=new List<int>(); Wait(owner.Updates.SetBetaAsync(true,step=> { steps.Add(step);return step==1; })); Pump();
            if(owner.Updates.BetaEnabled || !steps.SequenceEqual(new[]{1,2}) || toggle.IsChecked!=false) throw new Exception("Cancellation must leave beta disabled");
            steps.Clear(); Wait(owner.Updates.SetBetaAsync(true,step=> { steps.Add(step);return true; })); Pump();
            if(!owner.Updates.BetaEnabled || !steps.SequenceEqual(new[]{1,2}) || toggle.IsChecked!=true) throw new Exception("Both confirmations must enable beta");
            var channel=Path.Combine(root,"update-channel.json"); var backup=channel+".backup";
            File.Move(channel,backup); Directory.CreateDirectory(channel);
            Wait(owner.Updates.SetBetaAsync(false,_=>true)); owner.Updates.Check(manual:true); Pump();
            if(!owner.Updates.BetaEnabled || toggle.IsChecked!=true || owner.Updates.BetaError is not { } error || !error.Contains("未能保存") || !Tree(window).OfType<TextBlock>().Any(t=>t.Text.Contains("未能保存"))) throw new Exception("Failed disable must remain visible after a check");
            Directory.Delete(channel); File.Move(backup,channel);
            Wait(owner.Updates.SetBetaAsync(false,_=>throw new Exception("Disable must not ask to enable"))); Pump();
            if(owner.Updates.BetaEnabled || toggle.IsChecked!=false || owner.Updates.BetaError is not null) throw new Exception("Disable must persist and clear the error");
            window.Close();
        } finally { Directory.Delete(root,true); }
        Console.WriteLine("PASS Windows native beta opt-in and settings state");
    }
}
