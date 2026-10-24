namespace QuotaBar.Windows;
/// A: fixed content rows and channel columns, preserving native focus and labels.
internal sealed class NotificationMatrixSettingsView : StackPanel {
 readonly Coordinator owner;
 readonly Copy copy;
 readonly bool dark;
 readonly NotificationCategory[] categories=[NotificationCategory.QuotaLow,NotificationCategory.QuotaExhausted,NotificationCategory.QuotaRecovered,NotificationCategory.BankExpiring72h,NotificationCategory.BankExpiring24h,NotificationCategory.UpdateAvailable];
 readonly Dictionary<(NotificationCategory,NotificationChannel),CheckBox> cells=[];
 readonly Dictionary<NotificationChannel,CheckBox> masters=[];
 readonly TextBlock status;
 readonly ComboBox threshold;
 readonly Button pause;
 public NotificationMatrixSettingsView(Coordinator owner) {
  this.owner=owner; copy=owner.Copy; dark=Platform.IsDark(owner.Preferences); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark); status=Ui.Text("",11,muted); status.TextWrapping=TextWrapping.Wrap;
  var channels=new Grid();
  foreach(var channel in Enum.GetValues<NotificationChannel>()) {
   channels.ColumnDefinitions.Add(new()); var column=new StackPanel { Margin=new Thickness(0,0,12,0) };
   var box=SettingsVisual.Toggle(ChannelTitle(channel),owner.Notifications.PolicyPreferences.EnabledChannels.Contains(channel),fg,on=> { if(!owner.Notifications.SetChannelEnabled(channel,on)) status!.Text=copy.Text("Could not change channel. Check configuration or storage.","无法更改渠道，请检查配置或存储。","無法更改管道，請檢查設定或儲存。"); Refresh(); });
   box.Tag="notification.master."+Key(channel); masters[channel]=box; column.Children.Add(box);
   var label=channel switch { NotificationChannel.Bubble=>copy.Text("Independent channel","独立接收渠道","獨立接收管道"),NotificationChannel.System=>copy.Text("Controlled by system settings","由系统设置控制显示","由系統設定控制顯示"),_=>owner.Mobile.HasKey?copy.Text("Configured","已配置","已設定"):copy.Text("Not configured","未配置","未設定") };
   var note=Ui.Text(label,11,muted); note.TextWrapping=TextWrapping.Wrap; column.Children.Add(note); Grid.SetColumn(column,(int)channel); channels.Children.Add(column);
  }
  Children.Add(SettingsVisual.Card(channels,dark));
  var grid=new Grid(); grid.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star),MinWidth=180 });
  for(var i=0;i<3;i++) grid.ColumnDefinitions.Add(new() { Width=new GridLength(66) });
  AddRow(grid,0,Ui.Text(copy.Text("Reminder content","提醒内容","提醒內容"),13,fg));
  foreach(var channel in Enum.GetValues<NotificationChannel>()) Add(grid,0,(int)channel+1,Ui.Text(ChannelTitle(channel),12,muted));
  threshold=new ComboBox { ItemsSource=new[]{"10%","20%","30%"},Width=80,HorizontalAlignment=HorizontalAlignment.Left,Tag="notification.threshold",Margin=new Thickness(0,5,0,0) };
  System.Windows.Automation.AutomationProperties.SetName(threshold,copy.Text("Low remaining quota threshold","剩余额度偏低阈值","剩餘額度偏低閾值"));
  for(var i=0;i<categories.Length;i++) {
   var category=categories[i]; var label=new StackPanel { Margin=new Thickness(0,8,8,8) };
   label.Children.Add(Ui.Text(Title(category),13,fg)); var hint=Ui.Text(Hint(category),11,muted); hint.TextWrapping=TextWrapping.Wrap; label.Children.Add(hint);
   if(category==NotificationCategory.QuotaLow) label.Children.Add(threshold);
   AddRow(grid,i+1,label);
   foreach(var channel in Enum.GetValues<NotificationChannel>()) {
    var box=new CheckBox { IsChecked=owner.Notifications.PolicyPreferences.Rules.TryGetValue(category,out var selected)&&selected.Contains(channel),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,Tag="notification.rule."+Key(category)+"."+Key(channel) };
    System.Windows.Automation.AutomationProperties.SetName(box,Title(category)+" · "+ChannelTitle(channel)); cells[(category,channel)]=box;
    box.Click+=(_,_)=> { var p=owner.Notifications.PolicyPreferences; var rules=p.Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value)); if(!rules.TryGetValue(category,out var set)) rules[category]=set=[]; if(box.IsChecked==true) set.Add(channel); else set.Remove(channel); owner.Notifications.ConfigurePolicy(p with { Rules=rules }); Refresh(); };
    Add(grid,i+1,(int)channel+1,box);
   }
  }
  Children.Add(SettingsVisual.Card(grid,dark));
  var actions=new WrapPanel();
  pause=Ui.Button("",()=> { var p=owner.Notifications.PolicyPreferences; owner.Notifications.ConfigurePolicy(p with { BubblePausedUntil=p.BubblePausedUntil>DateTimeOffset.UtcNow?null:DateTimeOffset.UtcNow.AddHours(1) }); Refresh(); }); pause.Tag="notification.pause"; actions.Children.Add(pause);
  actions.Children.Add(Ui.Button(copy.Text("Preview bubble","预览气泡","預覽氣泡"),()=> { var m=new ExperienceNotification("preview-"+Guid.NewGuid(),ExperienceNotificationKind.Test,null,copy.Text("Example notification","示例通知","範例通知"),copy.Text("Example only. Quota and reminder history are unchanged.","仅为示例，不改变真实额度及提醒记录。","僅為範例，不改變真實額度及提醒記錄。"),DateTimeOffset.UtcNow); if(!owner.Notifications.Preview(m)) status.Text=copy.Text("Enable the floating button and close details to preview.","请开启悬浮按钮并收起详情后预览。","請開啟懸浮按鈕並收起詳情後預覽。"); }));
  actions.Children.Add(Ui.Button(copy.Text("Unread reminders","未读提醒","未讀提醒"),owner.ShowUnread)); Children.Add(actions);
  var footer=Ui.Text(copy.Text("Pause affects bubbles only. Enabling a channel does not replay past reminders. Configure mobile push on its settings page.","暂停仅影响气泡，开启渠道不补发历史提醒。手机推送请在手机推送页配置。","暫停僅影響氣泡，開啟管道不補發歷史提醒。手機推播請在手機推播頁設定。"),11,muted); footer.TextWrapping=TextWrapping.Wrap; footer.Margin=new Thickness(0,8,0,8); Children.Add(footer);
  Children.Add(status);
  if(!owner.Preferences.FloatingEnabled) Children.Add(Ui.Button(copy.Text("Enable floating button","开启悬浮按钮","開啟懸浮按鈕"),()=>owner.Save(owner.Preferences with { FloatingEnabled=true })));
  Refresh();
  threshold.SelectionChanged+=(_,_)=> { if(threshold.SelectedIndex>=0) { owner.Notifications.ConfigurePolicy(owner.Notifications.PolicyPreferences with { LowRemainingThreshold=new[]{10,20,30}[threshold.SelectedIndex] }); Refresh(); } };
 }
 void Refresh() {
  var p=owner.Notifications.PolicyPreferences;
  foreach(var (key,box) in cells) box.IsChecked=p.Rules.TryGetValue(key.Item1,out var selected)&&selected.Contains(key.Item2);
  foreach(var (channel,box) in masters) box.IsChecked=p.EnabledChannels.Contains(channel);
  threshold.SelectedIndex=Array.IndexOf(new[]{10,20,30},p.LowRemainingThreshold);
  pause.Content=p.BubblePausedUntil>DateTimeOffset.UtcNow?copy.Text("Resume bubbles","恢复气泡","恢復氣泡"):copy.Text("Pause bubbles 1 hour","暂停气泡1小时","暫停氣泡1小時");
  System.Windows.Automation.AutomationProperties.SetName(pause,pause.Content.ToString());
  if(owner.Notifications.PolicyError) status.Text=copy.Text("Could not read or save reminder settings.","提醒设置读取或保存失败。","提醒設定讀取或儲存失敗。");
 }
 static string Key<T>(T value) where T:Enum { var name=value.ToString(); return char.ToLowerInvariant(name[0])+name[1..]; }
 static void Add(Grid grid,int row,int column,UIElement child) { Grid.SetRow(child,row); Grid.SetColumn(child,column); grid.Children.Add(child); }
 static void AddRow(Grid grid,int row,UIElement label) { grid.RowDefinitions.Add(new() { Height=GridLength.Auto }); Add(grid,row,0,label); }
 string ChannelTitle(NotificationChannel c)=>c switch { NotificationChannel.Bubble=>copy.Text("Bubble","气泡","氣泡"),NotificationChannel.System=>copy.Text("System","系统","系統"),_=>copy.Text("Mobile","手机","手機") };
 string Title(NotificationCategory c)=>c switch { NotificationCategory.QuotaLow=>copy.Text("Quota low","额度偏低","額度偏低"),NotificationCategory.QuotaExhausted=>copy.Text("Quota depleted","额度耗尽","額度耗盡"),NotificationCategory.QuotaRecovered=>copy.Text("Quota restored","额度恢复","額度恢復"),NotificationCategory.BankExpiring72h=>copy.Text("Bank · 72 hours","Bank · 提前72小时","Bank · 提前72小時"),NotificationCategory.BankExpiring24h=>copy.Text("Bank · 24 hours","Bank · 提前24小时","Bank · 提前24小時"),_=>copy.Text("Software update","软件有新版本","軟體有新版本") };
 string Hint(NotificationCategory c)=>c switch { NotificationCategory.QuotaLow=>copy.Text("When remaining quota crosses this threshold.","剩余额度跨过阈值时提醒。","剩餘額度跨過閾值時提醒。"),NotificationCategory.QuotaExhausted=>copy.Text("When either quota window runs out.","任一额度周期耗尽时提醒。","任一額度週期耗盡時提醒。"),NotificationCategory.QuotaRecovered=>copy.Text("After confirmed recovery; animation is separate.","确认恢复后提醒，庆祝动画独立。","確認恢復後提醒，慶祝動畫獨立。"),NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h=>copy.Text("Known reset credits expiring soon.","已知重置权益即将到期。","已知重置權益即將到期。"),_=>copy.Text("Respects skipped versions and remind later.","遵循跳过版本和稍后提醒设置。","遵循略過版本與稍後提醒設定。") };
}
