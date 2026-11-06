using System;
using System.Collections.Generic;
using System.Linq;
using System.IO;
using System.Windows.Media.Imaging;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using QuotaBar.Core;
using QuotaBar.Windows;

internal static class AccountQuotaOverviewNativeTests {
    static IEnumerable<DependencyObject> Tree(DependencyObject node) {
        yield return node;
        for(var index=0;index<VisualTreeHelper.GetChildrenCount(node);index++) foreach(var child in Tree(VisualTreeHelper.GetChild(node,index))) yield return child;
    }
    static string Text(DependencyObject view)=>string.Join("\n",Tree(view).OfType<TextBlock>().Select(t=>t.Text));
    static QuotaSnapshot Snapshot(int count=3,bool secondary=true) {
        var now=DateTimeOffset.Now;
        return new(new(28,72,now.AddHours(3),300),secondary?new(36,64,now.AddDays(6),10080):null,"Plus",new(false,false,null),
            new(count,Enumerable.Range(0,count).Select(i=>new BankCredit("available",now,now.AddDays(i+1),null,null)).ToArray()),now);
    }
    public static void Run(Application app) {
        foreach(var language in new[]{"en","zh-CN","zh-TW"}) foreach(var dark in new[]{false,true}) {
            var copy=new Copy(language); var view=new AccountQuotaOverview();
            var scroll=new ScrollViewer { Content=view,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
            var window=new Window { Width=900,Height=700,Content=scroll,Background=Ui.Surface(dark),ShowInTaskbar=false };
            window.Show();
            try {
                var now=DateTime.Now;
                var usage=new TokenUsage(Enumerable.Range(0,7).Select(i=>new TokenDay(DateOnly.FromDateTime(now).AddDays(i-6),1000L*(i+1))).ToArray(),null,null,null,null,null);
                view.Update(Snapshot(),usage,copy,dark,"",true);
                foreach(var width in new[]{550d,900d}) {
                    window.Width=width; window.UpdateLayout();
                    if(Tree(view).OfType<TextBlock>().Count(t=>Equals(t.Tag,"account.quota.percent"))!=2) throw new Exception("Both quota windows must be visible");
                    var bank=Tree(view).OfType<Border>().Single(b=>Equals(b.Tag,"account.bank"));
                    var tokens=Tree(view).OfType<Border>().Single(b=>Equals(b.Tag,"account.tokens"));
                    var bankOrigin=bank.TranslatePoint(new Point(),view); var tokenOrigin=tokens.TranslatePoint(new Point(),view);
                    if(view.ActualWidth<760 && bankOrigin.Y<tokenOrigin.Y+tokens.ActualHeight-1) throw new Exception("Narrow account details must stack");
                    if(view.ActualWidth>=760 && bankOrigin.X<tokenOrigin.X+tokens.ActualWidth-1) throw new Exception("Wide account details must be side by side");
                }
                if(Environment.GetEnvironmentVariable("QUOTABAR_TEST_ARTIFACTS") is { Length:>0 } output && language=="zh-CN") {
                    Directory.CreateDirectory(output);
                    var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);
                    bitmap.Render(window);
                    var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file=File.Create(Path.Combine(output,"account-overview-"+(dark?"dark":"light")+".png")); encoder.Save(file);
                }
                view.Update(Snapshot(20,false),null,copy,dark,"Offline",false); window.UpdateLayout();
                if(!Text(view).Contains("Bank 20") || !Text(view).Contains(copy.NoData) || !Text(view).Contains("Offline")) throw new Exception("Every bank entry and missing Token state must remain visible");
                if(Tree(view).OfType<TextBlock>().Count(t=>Equals(t.Tag,"account.quota.percent"))!=1) throw new Exception("Missing secondary window must not fabricate a card");
                view.Update(null,null,copy,dark,"Sign in required",false); window.UpdateLayout();
                if(Tree(view).OfType<Border>().Any(b=>Equals(b.Tag,"account.bank")) || Tree(view).OfType<TextBlock>().Any(t=>Equals(t.Tag,"account.quota.percent"))) throw new Exception("Sign out must clear account quota");
            } finally { window.Close(); }
        }
        Console.WriteLine("PASS Windows account quota overview, responsive layout, missing data and sign-out");
    }
}
