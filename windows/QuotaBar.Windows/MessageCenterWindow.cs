using System.Windows.Automation;
using System.Windows.Data;
using System.Windows.Markup;
namespace QuotaBar.Windows;

/// Local archive viewer. Selection restoration is never a user read operation.
internal sealed class MessageCenterWindow : Window {
 readonly AppNotificationRouter router;
 readonly Copy copy;
 readonly bool dark;
 readonly Grid body=new();
 readonly Grid listPane=new() { Tag="messages.listPane" };
 readonly ListBox list=new() { Tag="messages.list",IsSynchronizedWithCurrentItem=false,HorizontalContentAlignment=HorizontalAlignment.Stretch };
 readonly TabControl tabs=new() { Tag="messages.tabs",Height=36,HorizontalAlignment=HorizontalAlignment.Left };
 readonly ScrollViewer detail=new() { Tag="messages.detailScroll",VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled };
 readonly TextBlock empty=new() { Tag="messages.empty",Margin=new Thickness(18),TextWrapping=TextWrapping.Wrap };
 readonly TextBlock error=new() { Tag="messages.storageError",TextWrapping=TextWrapping.Wrap };
 readonly TextBlock footer=new() { Tag="messages.localStatus",FontSize=11,TextWrapping=TextWrapping.Wrap };
 readonly Button allRead,back,retry;
 readonly StackPanel errorPane=new() { Margin=new Thickness(0,4,0,10) };
 bool refreshing,showingDetail;
 MessageCenterKey? renderedKey;
 public MessageCenterKey? SelectedKey { get; private set; }
 sealed record Row(MessageCenterRecord Record,string Date,string Dot,string Symbol,string AccessibleName) {
  public string Title=>Record.Title;
  public string Summary=>Record.Body.Replace('\n',' ');
 }
 public MessageCenterWindow(AppNotificationRouter router,Copy copy,bool dark) {
  this.router=router;this.copy=copy;this.dark=dark;
  Title=copy.Text("Messages","消息提醒","訊息提醒");Icon=Ui.ApplicationIcon;
  var area=SystemParameters.WorkArea;MinWidth=Math.Min(680,Math.Max(360,area.Width-40));MinHeight=Math.Min(440,Math.Max(300,area.Height-40));
  Width=Math.Min(900,area.Width-40);Height=Math.Min(600,area.Height-40);WindowStartupLocation=WindowStartupLocation.CenterScreen;
  Background=Ui.Surface(dark);Foreground=Ui.Foreground(dark);
  var root=new Grid { Margin=new Thickness(16) };Content=root;
  for(var i=0;i<6;i++) root.RowDefinitions.Add(new() { Height=i==4?new GridLength(1,GridUnitType.Star):GridLength.Auto });
  var header=new Grid { Margin=new Thickness(0,0,0,14) };var brand=new StackPanel { Orientation=Orientation.Horizontal };
  brand.Children.Add(Ui.ApplicationLogo());var brandName=Ui.Text("QuotaBar",15,Foreground);brandName.Margin=new Thickness(8,0,0,0);brand.Children.Add(brandName);header.Children.Add(brand);
  var heading=Ui.Text(Title,19,Foreground);heading.FontWeight=FontWeights.SemiBold;heading.HorizontalAlignment=HorizontalAlignment.Center;header.Children.Add(heading);root.Children.Add(header);
  var toolbar=new Grid { Margin=new Thickness(0,0,0,12) };toolbar.ColumnDefinitions.Add(new() { Width=new GridLength(1,GridUnitType.Star) });toolbar.ColumnDefinitions.Add(new() { Width=GridLength.Auto });
  tabs.Items.Add(new TabItem { Header=copy.Text("Unread reminders","未读提醒","未讀提醒") });tabs.Items.Add(new TabItem { Header=copy.Text("History","历史消息","歷史訊息") });tabs.SelectedIndex=0;
  toolbar.Children.Add(tabs);allRead=Button(copy.Text("Mark all read","全部已读","全部已讀"),"messages.allRead",()=>router.MarkAllMessagesRead());Grid.SetColumn(allRead,1);toolbar.Children.Add(allRead);Grid.SetRow(toolbar,1);root.Children.Add(toolbar);
  error.Foreground=Foreground;errorPane.Children.Add(error);retry=Button(copy.Text("Retry storage","重试存储","重試儲存"),"messages.retry",()=>router.RetryMessageStorage());errorPane.Children.Add(retry);Grid.SetRow(errorPane,2);root.Children.Add(errorPane);
  back=Button(copy.Text("Back to list","返回列表","返回清單"),"messages.back",()=> { showingDetail=false;LayoutPanes(); });back.Margin=new Thickness(0,0,0,8);Grid.SetRow(back,3);root.Children.Add(back);
  body.ColumnDefinitions.Add(new() { Width=new GridLength(0.38,GridUnitType.Star) });body.ColumnDefinitions.Add(new() { Width=new GridLength(12) });body.ColumnDefinitions.Add(new() { Width=new GridLength(0.62,GridUnitType.Star) });
  list.Background=Ui.Surface(dark);list.Foreground=Foreground;list.BorderBrush=SettingsVisual.Muted(dark);list.BorderThickness=new Thickness(0.5);
  VirtualizingPanel.SetIsVirtualizing(list,true);VirtualizingPanel.SetVirtualizationMode(list,VirtualizationMode.Recycling);ScrollViewer.SetCanContentScroll(list,true);ScrollViewer.SetHorizontalScrollBarVisibility(list,ScrollBarVisibility.Disabled);
  list.ItemTemplate=(DataTemplate)XamlReader.Parse("""
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"><Grid Height="82" Margin="6,0"><Grid.ColumnDefinitions><ColumnDefinition Width="10"/><ColumnDefinition Width="24"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="{Binding Dot}" Foreground="#3084E0" VerticalAlignment="Center" FontSize="10"/><TextBlock Grid.Column="1" Text="{Binding Symbol}" FontSize="18" VerticalAlignment="Center"/><StackPanel Grid.Column="2" VerticalAlignment="Center" Margin="8,0,4,0"><TextBlock Text="{Binding Title}" FontSize="13" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/><TextBlock Text="{Binding Summary}" FontSize="11" Opacity="0.75" TextTrimming="CharacterEllipsis" Margin="0,4,0,4"/><TextBlock Text="{Binding Date}" FontSize="10" Opacity="0.75"/></StackPanel></Grid></DataTemplate>
""");
  var style=new Style(typeof(ListBoxItem));style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty,HorizontalAlignment.Stretch));style.Setters.Add(new Setter(AutomationProperties.NameProperty,new Binding("AccessibleName")));list.ItemContainerStyle=style;
  listPane.Children.Add(list);empty.Foreground=SettingsVisual.Muted(dark);empty.IsHitTestVisible=false;listPane.Children.Add(empty);body.Children.Add(listPane);Grid.SetColumn(detail,2);body.Children.Add(detail);Grid.SetRow(body,4);root.Children.Add(body);
  footer.Foreground=SettingsVisual.Muted(dark);footer.Margin=new Thickness(0,12,0,0);Grid.SetRow(footer,5);root.Children.Add(footer);
  tabs.SelectionChanged+=(_,e)=> { if(!ReferenceEquals(e.Source,tabs)||refreshing) return;showingDetail=false;Refresh(); };
  list.SelectionChanged+=(_,_)=> { if(!refreshing&&list.SelectedItem is Row row) Open(row); };
  list.KeyDown+=(_,e)=> { if(e.Key==Key.Enter&&list.SelectedItem is Row row) { Open(row);e.Handled=true; } };
  list.PreviewMouseLeftButtonDown+=(_,e)=> { if(e.OriginalSource is DependencyObject target) { var item=ItemsControl.ContainerFromElement(list,target) as ListBoxItem;if(item?.IsSelected==true&&item.Content is Row row) { Open(row);e.Handled=true; } } };
  SizeChanged+=(_,_)=>LayoutPanes();router.MessageCenterChanged+=Refresh;Closed+=(_,_)=>router.MessageCenterChanged-=Refresh;
  SettingsVisual.ApplyScrollbars(root,dark);SettingsVisual.ApplyButtons(root,dark);Refresh();
 }
 Button Button(string title,string tag,Action action) { var b=Ui.Button(title,()=> { action();Refresh(); });b.Tag=tag;return b; }
 void Open(Row row) { SelectedKey=row.Record.Key;showingDetail=true;router.MarkMessageRead(row.Record.Key);Refresh(); }
 public void Refresh() {
  if(refreshing) return;refreshing=true;
  try {
   ((TabItem)tabs.Items[0]).Header=copy.Text("Unread reminders","未读提醒","未讀提醒")+" ("+router.MessageUnreadCount+")";
   var records=router.MessageHistory;var visible=tabs.SelectedIndex==0?records.Where(r=>r.ReadAtMilliseconds==null):records;
   var rows=visible.Select(r=>new Row(r,r.CreatedAt.ToLocalTime().ToString("g"),r.ReadAtMilliseconds==null?"●":"",r.Category switch { NotificationCategory.QuotaRecovered=>"↻",NotificationCategory.UpdateAvailable=>"↑",NotificationCategory.BankExpiring72h or NotificationCategory.BankExpiring24h=>"◷",_=>"!" },(r.ReadAtMilliseconds==null?copy.Text("Unread","未读","未讀"):copy.Text("Read","已读","已讀"))+": "+r.Title)).ToArray();
   list.ItemsSource=rows;list.SelectedItem=rows.FirstOrDefault(r=>r.Record.Key==SelectedKey);
   empty.Text=tabs.SelectedIndex==0?copy.Text("No unread reminders","暂无未读提醒","目前沒有未讀提醒"):copy.Text("No messages yet","暂无历史消息","目前沒有歷史訊息");empty.Visibility=rows.Length==0?Visibility.Visible:Visibility.Collapsed;
   var failed=router.MessageStorageError!=null;errorPane.Visibility=failed?Visibility.Visible:Visibility.Collapsed;error.Visibility=failed?Visibility.Visible:Visibility.Collapsed;
   error.Text=copy.Text("Message storage unavailable. Original file preserved; new messages may be temporary. ","消息存储不可用，原文件已保留，新消息可能尚未保存。","訊息儲存無法使用，原檔案已保留，新訊息可能尚未儲存。")+router.MessageStorageError;
   allRead.IsEnabled=!failed&&router.MessageUnreadCount>0;
   footer.Text=router.MessageHasUnpersistedMessages?copy.Text("Some messages are temporary. Retry storage to save them.","部分消息尚未保存，请重试存储。","部分訊息尚未儲存，請重試儲存。"):copy.Text("Saved locally · history is not automatically deleted","保存在本机 · 历史消息不自动删除","儲存在本機 · 歷史訊息不自動刪除");
   RenderDetail(records.FirstOrDefault(r=>r.Key==SelectedKey));LayoutPanes();
  } finally { refreshing=false; }
 }
 void RenderDetail(MessageCenterRecord? record) {
  var offset=renderedKey==record?.Key?detail.VerticalOffset:0;renderedKey=record?.Key;
  var column=new StackPanel { Margin=new Thickness(18,12,18,12) };detail.Content=column;
  void Text(string text,double size=12,bool muted=false,string? tag=null) { var t=Ui.Text(text,size,muted?SettingsVisual.Muted(dark):Foreground);t.Margin=new Thickness(0,0,0,12);t.Tag=tag;column.Children.Add(t); }
  if(record==null) { Text(copy.Text("Select a message to view details","选择消息查看详情","選取訊息查看詳細內容"),14,true);return; }
  Text(record.Title,18);Text(record.CreatedAt.ToLocalTime().ToString("g")+" · "+(record.ReadAtMilliseconds==null?copy.Text("Unread","未读","未讀"):copy.Text("Read","已读","已讀")),11,true);
  if(record.Key.Epoch!=null&&record.Key.Epoch!=router.CurrentMessageEpoch) Text(copy.Text("Earlier session · recorded quota snapshot","历史会话 · 以下为当时的额度记录","歷史工作階段 · 以下為當時的額度記錄"),11,true);
  var channels=Enum.GetValues<NotificationChannel>().Where(record.Channels.Contains).Select(c=>c switch { NotificationChannel.Bubble=>copy.Text("Bubble","气泡通知","氣泡通知"),NotificationChannel.System=>copy.Text("System","系统通知","系統通知"),_=>copy.Text("Mobile","手机推送","手機推播") });
  Text(copy.Text("Configured channels: ","提醒渠道：","提醒管道：")+string.Join(" · ",channels),11,true);Text(record.Body,14,tag:"messages.detail.body");
  Text(copy.Text("This is the message as recorded at the time. View current quota for the latest status.","以上为消息产生时的记录，最新状态请查看当前额度。","以上為訊息產生時的記錄，最新狀態請查看目前額度。"),11,true);
  if(!router.IsMessagePersisted(record.Key)) Text(copy.Text("Not saved to disk yet","尚未保存到磁盘","尚未儲存至磁碟"),11,true);
  var latest=Button(record.Category==NotificationCategory.UpdateAvailable?copy.Text("View update","查看更新","查看更新"):copy.Text("View current quota","查看当前额度","查看目前額度"),"messages.latest",()=>router.OpenMessageLatest(record));latest.IsEnabled=record.Category==NotificationCategory.UpdateAvailable?router.SystemUpdateRequested!=null:router.MessageDetailsRequested!=null;column.Children.Add(latest);
  var read=Button(copy.Text("Mark as read","标为已读","標為已讀"),"messages.markRead",()=>router.MarkMessageRead(record.Key));read.IsEnabled=record.ReadAtMilliseconds==null&&router.MessageStorageError==null;column.Children.Add(read);SettingsVisual.ApplyButtons(column,dark);
  detail.UpdateLayout();detail.ScrollToVerticalOffset(offset);
 }
 void LayoutPanes() {
  var compact=ActualWidth<760;var show=showingDetail&&SelectedKey!=null;
  body.ColumnDefinitions[0].Width=new GridLength(compact?1:0.38,GridUnitType.Star);body.ColumnDefinitions[1].Width=new GridLength(compact?0:12);body.ColumnDefinitions[2].Width=compact?new GridLength(0):new GridLength(0.62,GridUnitType.Star);
  Grid.SetColumn(detail,compact?0:2);listPane.Visibility=compact&&show?Visibility.Collapsed:Visibility.Visible;detail.Visibility=!compact||show?Visibility.Visible:Visibility.Collapsed;back.Visibility=compact&&show?Visibility.Visible:Visibility.Collapsed;
 }
}
