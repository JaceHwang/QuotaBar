namespace QuotaBar.Windows;
/// A: fixed content rows and channel columns, preserving native focus and labels.
internal sealed class NotificationMatrixSettingsView : StackPanel {
 readonly Coordinator owner;
 readonly Copy copy;
 readonly bool dark;
 readonly NotificationCategory[] categories=[NotificationCategory.QuotaExhausted,NotificationCategory.QuotaRecovered,NotificationCategory.QuotaLow,NotificationCategory.BankExpiring72h,NotificationCategory.UpdateAvailable];
 readonly Dictionary<(NotificationCategory,NotificationChannel),CheckBox> cells=[];
 readonly Dictionary<NotificationChannel,CheckBox> masters=[];
 readonly TextBlock status;
 readonly Dictionary<NotificationChannel,Button> columnActions=[];
 readonly Button pause;
 readonly Button test;
 bool refreshing;
 public NotificationMatrixSettingsView(Coordinator owner) {
  this.owner=owner; copy=owner.Copy; dark=Platform.IsDark(owner.Preferences); var fg=Ui.Foreground(dark); var muted=SettingsVisual.Muted(dark); status=Ui.Text("",11,muted); status.TextWrapping=TextWrapping.Wrap;
  var channels=new Grid();
  foreach(var channel in Enum.GetValues<NotificationChannel>()) {
   channels.ColumnDefinitions.Add(new()); var column=new StackPanel { Margin=new Thickness(0,0,12,0) };
   var box=SettingsVisual.Toggle(MasterTitle(channel),owner.Notifications.PolicyPreferences.EnabledChannels.Contains(channel),fg,on=> { if(refreshing) return; if(!owner.Notifications.SetChannelEnabled(channel,on)) status!.Text=copy.Text("Could not change channel. Check configuration or storage.","无法更改渠道，请检查配置或存储。","無法更改管道，請檢查設定或儲存。"); Refresh(); },compact:true);
   box.Tag="notification.master."+Key(channel); masters[channel]=box; column.Children.Add(box);
   var label=channel switch { NotificationChannel.Bubble=>copy.Text("Independent channel","独立接收渠道","獨立接收管道"),NotificationChannel.System=>copy.Text("Controlled by system settings","由系统设置控制显示","由系統設定控制顯示"),_=>owner.Mobile.HasKey?copy.Text("Configured","已配置","已設定"):copy.Text("Not configured","未配置","未設定") };
   var note=Ui.Text(label,11,muted); note.TextWrapping=TextWrapping.Wrap; column.Children.Add(note); Grid.SetColumn(column,(int)channel); channels.Children.Add(column);
  }
  Children.Add(SettingsVisual.Card(channels,dark));
  var grid=new Grid(); grid.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star),MinWidth=210 });
  for(var i=0;i<3;i++) grid.ColumnDefinitions.Add(new() { Width=new GridLength(66) });
  AddRow(grid,0,Ui.Text(copy.Text("Reminder content","提醒内容","提醒內容"),13,fg));
  foreach(var channel in Enum.GetValues<NotificationChannel>()) {
   var heading=new StackPanel { HorizontalAlignment=HorizontalAlignment.Center };
   heading.Children.Add(Ui.Text(ChannelTitle(channel),12,muted));
   var select=Ui.Button(copy.Text("Select all","全选","全選"),()=> { var p=owner.Notifications.PolicyPreferences; if(p.EnabledChannels.Contains(channel)) owner.Notifications.ConfigurePolicy(p.ToggleColumn(channel)); Refresh(); });
   select.Tag="notification.selectAll."+Key(channel); columnActions[channel]=select;
   System.Windows.Automation.AutomationProperties.SetName(select,ChannelTitle(channel)+" · "+copy.Text("Select all","全选","全選"));
   heading.Children.Add(select); Add(grid,0,(int)channel+1,heading);
  }
  for(var i=0;i<categories.Length;i++) {
   var category=categories[i]; var label=new StackPanel { Margin=new Thickness(0,8,8,8) };
   var name=Ui.Text(Title(category),13,fg); name.VerticalAlignment=VerticalAlignment.Center;
   if(category is NotificationCategory.QuotaLow or NotificationCategory.BankExpiring72h) {
    var bank=category==NotificationCategory.BankExpiring72h;
    label.Children.Add(new DynamicThresholdChipsView(name,bank?"bank":"low",bank?8760:99,bank?copy.Text("h","小时","小時"):"%",copy,dark,
     ()=>bank?owner.Notifications.PolicyPreferences.ConfiguredBankHours:owner.Notifications.PolicyPreferences.ConfiguredLowThresholds,
     (values,aliases)=> { var p=owner.Notifications.PolicyPreferences; owner.Notifications.ConfigurePolicy(bank?p.WithBankHours(values,aliases):p.WithLowThresholds(values)); Refresh(); }));
   } else label.Children.Add(name);
   var hint=Ui.Text(Hint(category),11,muted); hint.TextWrapping=TextWrapping.Wrap; label.Children.Add(hint);
   AddRow(grid,i+1,label);
   foreach(var channel in Enum.GetValues<NotificationChannel>()) {
    var box=new CheckBox { IsChecked=owner.Notifications.PolicyPreferences.Rules.TryGetValue(category,out var selected)&&selected.Contains(channel),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Top,Margin=new Thickness(0,10,0,0),Tag="notification.rule."+Key(category)+"."+Key(channel),IsThreeState=category==NotificationCategory.BankExpiring72h };
    System.Windows.Automation.AutomationProperties.SetName(box,Title(category)+" · "+ChannelTitle(channel)); cells[(category,channel)]=box;
    box.Click+=(_,_)=> { if(!owner.Notifications.PolicyPreferences.EnabledChannels.Contains(channel)) { Refresh(); return; } var p=owner.Notifications.PolicyPreferences; if(category==NotificationCategory.BankExpiring72h) { owner.Notifications.ConfigurePolicy(p.WithBankChannel(channel,p.BankChannelSelected(channel)!=true)); Refresh(); return; } var rules=p.Rules.ToDictionary(r=>r.Key,r=>new HashSet<NotificationChannel>(r.Value)); if(!rules.TryGetValue(category,out var set)) rules[category]=set=[]; if(box.IsChecked==true) set.Add(channel); else set.Remove(channel); owner.Notifications.ConfigurePolicy(p with { Rules=rules }); Refresh(); };
    Add(grid,i+1,(int)channel+1,box);
   }
  }
  Children.Add(SettingsVisual.Card(grid,dark));
  test=Ui.Button(copy.Text("Send test notification","发送测试通知","傳送測試通知"),owner.Experience.TestNotification); test.Tag="notification.test"; Children.Add(test);
  var testHint=Ui.Text(copy.Text("Tests use the enabled channel switches above, independently of category selections.","按上方已开启的渠道测试，不受分类勾选影响。","依上方已開啟的管道測試，不受分類勾選影響。"),11,muted); testHint.TextWrapping=TextWrapping.Wrap; Children.Add(testHint);
  var actions=new WrapPanel();
  pause=Ui.Button("",()=> { var p=owner.Notifications.PolicyPreferences; owner.Notifications.ConfigurePolicy(p with { BubblePausedUntil=p.BubblePausedUntil>DateTimeOffset.UtcNow?null:DateTimeOffset.UtcNow.AddHours(1) }); Refresh(); }); pause.Tag="notification.pause"; actions.Children.Add(pause);
  actions.Children.Add(Ui.Button(copy.Text("Preview bubble","预览气泡","預覽氣泡"),()=> { var m=new ExperienceNotification("preview-"+Guid.NewGuid(),ExperienceNotificationKind.Test,null,copy.Text("Example notification","示例通知","範例通知"),copy.Text("Example only. Quota and reminder history are unchanged.","仅为示例，不改变真实额度及提醒记录。","僅為範例，不改變真實額度及提醒記錄。"),DateTimeOffset.UtcNow); if(!owner.Notifications.Preview(m)) status.Text=copy.Text("Enable the floating button and close details to preview.","请开启悬浮按钮并收起详情后预览。","請開啟懸浮按鈕並收起詳情後預覽。"); }));
  actions.Children.Add(Ui.Button(copy.Text("Unread reminders","未读提醒","未讀提醒"),owner.ShowUnread)); Children.Add(actions);
  var footer=Ui.Text(copy.Text("Pause affects bubbles only. Enabling a channel does not replay past reminders. Configure mobile push on its settings page.","暂停仅影响气泡，开启渠道不补发历史提醒。手机推送请在手机推送页配置。","暫停僅影響氣泡，開啟管道不補發歷史提醒。手機推播請在手機推播頁設定。"),11,muted); footer.TextWrapping=TextWrapping.Wrap; footer.Margin=new Thickness(0,8,0,8); Children.Add(footer);
  Children.Add(status);
  if(!owner.Preferences.FloatingEnabled) Children.Add(Ui.Button(copy.Text("Enable floating button","开启悬浮按钮","開啟懸浮按鈕"),()=>owner.Save(owner.Preferences with { FloatingEnabled=true })));
  Refresh();
 }
 void Refresh() {
  refreshing=true;
  var p=owner.Notifications.PolicyPreferences;
  foreach(var (key,box) in cells) { box.IsChecked=key.Item1==NotificationCategory.BankExpiring72h?p.BankChannelSelected(key.Item2):p.Rules.TryGetValue(key.Item1,out var selected)&&selected.Contains(key.Item2); box.IsEnabled=p.EnabledChannels.Contains(key.Item2); box.Opacity=box.IsEnabled?1:0.45; }
  test.IsEnabled=p.EnabledChannels.Count>0;
  foreach(var (channel,box) in masters) box.IsChecked=p.EnabledChannels.Contains(channel);
  foreach(var (channel,button) in columnActions) button.IsEnabled=p.EnabledChannels.Contains(channel);
  pause.Content=p.BubblePausedUntil>DateTimeOffset.UtcNow?copy.Text("Resume bubbles","恢复气泡","恢復氣泡"):copy.Text("Pause bubbles 1 hour","暂停气泡1小时","暫停氣泡1小時");
  System.Windows.Automation.AutomationProperties.SetName(pause,pause.Content.ToString());
  refreshing=false;
  if(owner.Notifications.PolicyError) status.Text=copy.Text("Could not read or save reminder settings.","提醒设置读取或保存失败。","提醒設定讀取或儲存失敗。");
 }
 static string Key<T>(T value) where T:Enum { var name=value.ToString(); return char.ToLowerInvariant(name[0])+name[1..]; }
 static void Add(Grid grid,int row,int column,UIElement child) { Grid.SetRow(child,row); Grid.SetColumn(child,column); grid.Children.Add(child); }
 static void AddRow(Grid grid,int row,UIElement label) { grid.RowDefinitions.Add(new() { Height=GridLength.Auto }); Add(grid,row,0,label); }
 string MasterTitle(NotificationChannel c)=>c switch { NotificationChannel.Bubble=>copy.Text("Bubble notifications","气泡通知","氣泡通知"),NotificationChannel.System=>copy.Text("System notifications","系统通知","系統通知"),_=>copy.Text("Mobile push notifications","手机推送通知","手機推播通知") };
 string ChannelTitle(NotificationChannel c)=>c switch { NotificationChannel.Bubble=>copy.Text("Bubble","气泡","氣泡"),NotificationChannel.System=>copy.Text("System","系统","系統"),_=>copy.Text("Mobile","手机","手機") };
 string Title(NotificationCategory c)=>c switch { NotificationCategory.QuotaLow=>copy.Text("Quota low","额度偏低","額度偏低"),NotificationCategory.QuotaExhausted=>copy.Text("Quota depleted","额度耗尽","額度耗盡"),NotificationCategory.QuotaRecovered=>copy.Text("Quota restored","额度恢复","額度恢復"),NotificationCategory.BankExpiring72h=>copy.Text("Bank expiry","Bank 到期","Bank 到期"),NotificationCategory.BankExpiring24h=>copy.Text("Bank · 24 hours","Bank · 提前24小时","Bank · 提前24小時"),_=>copy.Text("Software update","软件有新版本","軟體有新版本") };
 string Hint(NotificationCategory c)=>c switch { NotificationCategory.QuotaLow=>copy.Text("When remaining quota crosses this threshold.","剩余额度跨过阈值时提醒。","剩餘額度跨過閾值時提醒。"),NotificationCategory.QuotaExhausted=>copy.Text("When either quota window runs out.","任一额度周期耗尽时提醒。","任一額度週期耗盡時提醒。"),NotificationCategory.QuotaRecovered=>copy.Text("After confirmed recovery; animation is separate.","确认恢复后提醒，庆祝动画独立。","確認恢復後提醒，慶祝動畫獨立。"),NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h=>copy.Text("Known reset credits expiring soon.","已知重置权益即将到期。","已知重置權益即將到期。"),_=>copy.Text("Respects skipped versions and remind later.","遵循跳过版本和稍后提醒设置。","遵循略過版本與稍後提醒設定。") };
}
