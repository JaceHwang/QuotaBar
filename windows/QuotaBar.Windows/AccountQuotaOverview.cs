namespace QuotaBar.Windows;

/// Uses the floating detail window's formatting and rendering for the same snapshot.
internal sealed class AccountQuotaOverview : StackPanel {
    readonly Grid metrics = new();
    readonly Grid details = new();
    Border? tokenCard,bankCard;
    QuotaSnapshot? lastQuota;
    TokenUsage? lastTokens;
    string? lastState;
    bool lastCurrent;
    long lastMinute=-1;
    bool? split;

    public AccountQuotaOverview() {
        Tag="account.quotaOverview";
        SizeChanged+=(_,_)=>ArrangeSections();
    }

    public void Update(QuotaSnapshot? quota,TokenUsage? tokens,Copy copy,bool dark,string stateText,bool current) {
        var minute=DateTimeOffset.Now.ToUnixTimeSeconds()/60;
        if(Equals(lastQuota,quota) && Equals(lastTokens,tokens) && lastState==stateText && lastCurrent==current && lastMinute==minute) return;
        lastQuota=quota; lastTokens=tokens; lastState=stateText; lastCurrent=current; lastMinute=minute;
        Children.Clear(); metrics.Children.Clear(); details.Children.Clear(); split=null;
        if(quota is null || !current) {
            var state=Ui.Text(stateText,12,SettingsVisual.Muted(dark));
            state.TextWrapping=TextWrapping.Wrap; state.Margin=new Thickness(0,0,0,14); state.Tag="account.quotaState";
            Children.Add(state);
        }
        if(quota is null) return;
        var windows=new[]{quota.Primary,quota.Secondary}.OfType<QuotaWindow>().ToArray();
        foreach(var window in windows) {
            var column=new StackPanel();
            var heading=Ui.Text(copy.Period(window.WindowMinutes),15,Ui.Foreground(dark)); heading.FontWeight=FontWeights.SemiBold; column.Children.Add(heading);
            var percent=Ui.Text($"{window.RemainingPercent}%",34,current?Ui.ReadableQuotaAccent(window.RemainingPercent,dark):SettingsVisual.Muted(dark));
            percent.FontWeight=FontWeights.SemiBold; percent.Margin=new Thickness(0,8,0,10); percent.Tag="account.quota.percent"; column.Children.Add(percent);
            var bar=new ProgressBar { Foreground=SystemParameters.HighContrast?SystemColors.HighlightBrush:new SolidColorBrush(Color.FromRgb(0,101,216)),Minimum=0,Maximum=100,Value=window.RemainingPercent,Height=6,Margin=new Thickness(0,0,0,14) };
            System.Windows.Automation.AutomationProperties.SetName(bar,copy.Period(window.WindowMinutes)+$" {window.RemainingPercent}%"); column.Children.Add(bar);
            var reset=Ui.Text(copy.Text("Next reset","下次重置","下次重設")+"\n"+copy.DetailCountdown(window.ResetsAt,DateTimeOffset.Now)+"\n"+window.ResetsAt.ToLocalTime().ToString("yyyy/MM/dd HH:mm"),12,SettingsVisual.Muted(dark));
            reset.TextWrapping=TextWrapping.Wrap; reset.Tag="account.quota.reset"; column.Children.Add(reset);
            metrics.Children.Add(SettingsVisual.Card(column,dark));
        }
        Children.Add(metrics);
        var palette=DetailPalette.For(dark);
        var token=new StackPanel();
        token.Children.Add(DetailWindow.TokenBand(tokens,quota,copy,palette,expanded:true));
        var delay=Ui.Text(copy.Text("Usage statistics may be delayed.","用量统计可能延迟。","用量統計可能延遲。"),11,SettingsVisual.Muted(dark));
        delay.TextWrapping=TextWrapping.Wrap; delay.Margin=new Thickness(16,0,16,16); token.Children.Add(delay);
        tokenCard=SettingsVisual.Card(token,dark,new Thickness(0)); tokenCard.Tag="account.tokens";
        var bank=new StackPanel();
        var bankTitle=Ui.Text(copy.Text("Bank & credits","Bank 权益与 Credits","Bank 權益與 Credits"),15,Ui.Foreground(dark)); bankTitle.FontWeight=FontWeights.SemiBold; bankTitle.Margin=new Thickness(0,0,0,12); bank.Children.Add(bankTitle);
        bank.Children.Add(DetailWindow.BankDetails(quota,copy,palette));
        bankCard=SettingsVisual.Card(bank,dark); bankCard.Tag="account.bank";
        details.Children.Add(tokenCard); details.Children.Add(bankCard); Children.Add(details);
        ArrangeSections();
    }

    void ArrangeSections() {
        var wide=ActualWidth>=760;
        var metricColumns=ActualWidth>=480?Math.Max(1,metrics.Children.Count):1;
        metrics.ColumnDefinitions.Clear(); metrics.RowDefinitions.Clear();
        for(var i=0;i<metricColumns;i++) metrics.ColumnDefinitions.Add(new());
        for(var i=0;i<metrics.Children.Count;i++) {
            if(i%metricColumns==0) metrics.RowDefinitions.Add(new() { Height=GridLength.Auto });
            var child=(FrameworkElement)metrics.Children[i]; Grid.SetColumn(child,i%metricColumns); Grid.SetRow(child,i/metricColumns);
            child.Margin=new Thickness(i%metricColumns==0?0:7,0,i%metricColumns<metricColumns-1?7:0,14);
        }
        if(tokenCard is null || bankCard is null || split==wide) return;
        split=wide; details.ColumnDefinitions.Clear(); details.RowDefinitions.Clear();
        details.ColumnDefinitions.Add(new() { Width=new GridLength(wide?1.6:1,GridUnitType.Star) });
        if(wide) details.ColumnDefinitions.Add(new());
        details.RowDefinitions.Add(new() { Height=GridLength.Auto });
        if(!wide) details.RowDefinitions.Add(new() { Height=GridLength.Auto });
        Grid.SetColumn(bankCard,wide?1:0); Grid.SetRow(bankCard,wide?0:1);
        tokenCard.Margin=new Thickness(0,0,wide?7:0,14); bankCard.Margin=new Thickness(wide?7:0,0,0,14);
    }
}
