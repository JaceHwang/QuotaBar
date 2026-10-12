using System.Globalization;

namespace QuotaBar.Core;
public sealed class Copy(string language) {
    public string Language { get; }=language=="system" ? CultureInfo.CurrentUICulture.Name : language;
    public bool Chinese => Language.StartsWith("zh",StringComparison.OrdinalIgnoreCase);
    public bool Traditional => new[]{"zh-TW","zh-HK","zh-MO","zh-Hant"}.Any(code=>Language.StartsWith(code,StringComparison.OrdinalIgnoreCase));
    public string Text(string english,string chinese,string? traditional=null) => !Chinese?english:Traditional?traditional??chinese:chinese;
    public string Period(int? minutes) => minutes is null ? Text("Quota","额度","額度") : minutes%1440==0 ? $"{minutes/1440} "+Text("days","天") : minutes%60==0 ? $"{minutes/60} "+Text("hours","小时","小時") : $"{minutes} "+Text("minutes","分钟","分鐘");
    public string NoData => Text("Unavailable","暂无数据","暫無資料");
    public string PhaseLabel(Phase phase) => phase switch {
        Phase.Ready=>Text("Quota updated","额度已更新","額度已更新"),
        Phase.NeedsLogin=>Text("Sign in required","请登录","請登入"),
        Phase.SigningIn=>Text("Signing in…","正在登录…","正在登入…"),
        Phase.Offline=>Text("Offline · retrying","离线 · 正在重试","離線 · 正在重試"),
        Phase.Unsupported=>Text("Runtime unsupported","运行时不支持","執行環境不支援"),
        _=>Text("Loading…","正在读取…","正在讀取…")
    };
    public string Reset(DateTimeOffset reset) => reset.ToLocalTime().ToString(Chinese?"M月d日 HH:mm":"MMM d HH:mm",CultureInfo.CurrentCulture);
    public string Countdown(DateTimeOffset reset,DateTimeOffset now) {
        var interval=reset-now;
        if(interval<=TimeSpan.Zero) return Text("Reset due","即将重置","即將重設");
        return interval.TotalDays>=1 ? $"{(int)interval.TotalDays}"+Text("d ","天 ")+ $"{interval.Hours}"+Text("h","小时","小時") : interval.TotalHours>=1 ? $"{(int)interval.TotalHours}"+Text("h ","小时 ","小時 ")+ $"{interval.Minutes}"+Text("m","分钟","分鐘") : $"{Math.Max(1,interval.Minutes)}"+Text("m","分钟","分鐘");
    }
    public string Indicator(QuotaSnapshot? quota,Phase phase) {
        if(quota is null) return PhaseLabel(phase);
        string Line(QuotaWindow w)=>$"{Period(w.WindowMinutes)} {w.RemainingPercent}% · {Reset(w.ResetsAt)}";
        return Line(quota.Primary)+(quota.Secondary is { } second ? "\n"+Line(second) : "");
    }
}

public static class TokenWindow {
    public static IReadOnlyList<TokenDay> Days(TokenUsage usage,QuotaSnapshot allowance,DateTimeOffset now) {
        var window=allowance.Secondary??allowance.Primary;
        var end=DateOnly.FromDateTime((now<window.ResetsAt?now:window.ResetsAt).LocalDateTime);
        DateOnly start;
        try { start=window.WindowMinutes is int duration ? DateOnly.FromDateTime(window.ResetsAt.AddMinutes(-duration).LocalDateTime) : DateOnly.FromDateTime(now.LocalDateTime).AddDays(-6); }
        catch(ArgumentOutOfRangeException e) { throw new FormatException("Token window outside supported date range",e); }
        var values=new Dictionary<DateOnly,long>();
        foreach(var day in usage.Days.Where(d=>d.Date>=start && d.Date<=end)) {
            try { values[day.Date]=checked(values.GetValueOrDefault(day.Date)+day.Tokens); }
            catch(OverflowException) { throw new FormatException("Token total overflow"); }
        }
        try { return Enumerable.Range(0,7).Select(i=>new TokenDay(start.AddDays(i),values.GetValueOrDefault(start.AddDays(i)))).ToArray(); }
        catch(ArgumentOutOfRangeException e) { throw new FormatException("Token window outside supported date range",e); }
    }
    public static long Total(IReadOnlyList<TokenDay> days) {
        try { return days.Aggregate(0L,(a,d)=>checked(a+d.Tokens)); }
        catch(OverflowException) { throw new FormatException("Token total overflow"); }
    }
}

public static class QuotaColors {
    public static (byte R,byte G,byte B) ForPercent(int percent) {
        var v=Math.Clamp(percent,0,100);
        (double H,double S,double V) orange=(.078,.96,1),green=(.36,.78,.82),red=(0,.86,1),critical=(0,.96,.76);
        var a=v>=49?orange:v>=10?red:critical; var b=v>=49?green:v>=10?orange:red;
        var t=v>=49?(v-49)/51d:v>=10?(v-10)/39d:v/10d;
        var h=(a.H+(b.H-a.H)*t)*6; var s=a.S+(b.S-a.S)*t; var value=a.V+(b.V-a.V)*t;
        var c=value*s; var x=c*(1-Math.Abs(h%2-1)); var m=value-c;
        var rgb=h switch { <1=>(c,x,0d),<2=>(x,c,0d),<3=>(0d,c,x),<4=>(0d,x,c),<5=>(x,0d,c),_=>(c,0d,x) };
        return ((byte)Math.Round((rgb.Item1+m)*255),(byte)Math.Round((rgb.Item2+m)*255),(byte)Math.Round((rgb.Item3+m)*255));
    }
}
