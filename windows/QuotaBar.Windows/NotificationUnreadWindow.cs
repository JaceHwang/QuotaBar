namespace QuotaBar.Windows;
internal sealed class NotificationUnreadWindow : Window {
    public NotificationUnreadWindow(AppNotificationRouter router,Copy copy,bool dark) {
        Title=copy.Text("Unread reminders · this run only","未读提醒 · 仅本次运行","未讀提醒 · 僅本次執行"); Width=480; Height=440; Background=Ui.Surface(dark);
        var column=new StackPanel { Margin=new Thickness(16) }; Content=new ScrollViewer { Content=column,VerticalScrollBarVisibility=ScrollBarVisibility.Auto };
        if(router.Unread.Count==0) column.Children.Add(Ui.Text(copy.Text("No unread reminders","暂无未读提醒","目前沒有未讀提醒"),13,Ui.Foreground(dark)));
        foreach(var item in router.Unread) {
            var title=Ui.Text(item.Stale&&item.Message.Kind==ExperienceNotificationKind.Bank?copy.Text("Earlier Bank reminder","Bank 提醒记录","Bank 提醒記錄"):item.Message.Title,13,Ui.Foreground(dark)); title.FontWeight=FontWeights.SemiBold; column.Children.Add(title);
            column.Children.Add(Ui.Text(item.Message.CreatedAt.ToLocalTime().ToString("g"),11,Brushes.Gray));
            var body=item.Stale?copy.Text("Earlier observation. View current quota for the latest status.","此前观测的提醒，请查看最新额度状态。","先前觀測的提醒，請查看最新額度狀態。"):item.Message.Body;
            var text=Ui.Text(body,12,Ui.Foreground(dark)); text.TextWrapping=TextWrapping.Wrap; text.Margin=new Thickness(0,6,0,8); column.Children.Add(text);
            var row=new WrapPanel(); row.Children.Add(Ui.Button(copy.Text("View latest","查看最新","查看最新"),()=> { router.ActivateLatest(item.Message.Id); Close(); })); row.Children.Add(Ui.Button(copy.Text("Got it","知道了","知道了"),()=> { router.Dismiss(item.Message.Id,true); Close(); })); row.Margin=new Thickness(0,0,0,20); column.Children.Add(row);
        }
    }
}
