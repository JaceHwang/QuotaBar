namespace QuotaBar.Windows;
/// The approved matrix stays visible while storage errors are recoverable in place.
internal sealed class NotificationSettingsView : StackPanel {
    readonly Coordinator owner;
    public NotificationSettingsView(Coordinator owner) { this.owner=owner; Build(); }
    void Build() {
        Children.Clear();
        var copy=owner.Copy; var dark=Platform.IsDark(owner.Preferences);
        if(owner.Notifications.PolicyLoadFailed) {
            var error=Ui.Text(copy.Text(
                "Reminder settings could not be loaded. The matrix is read-only until loading succeeds; previous reminder behavior is preserved.",
                "提醒配置未能载入，矩阵暂不可编辑；原提醒行为保持不变。",
                "提醒設定未能載入，矩陣暫不可編輯；原提醒行為保持不變。"),12,SettingsVisual.Muted(dark));
            error.TextWrapping=TextWrapping.Wrap; error.Tag="notification.policy.error"; Children.Add(error);
            var detail=Ui.Text(owner.Notifications.PolicyFailure??"",11,SettingsVisual.Muted(dark)); detail.TextWrapping=TextWrapping.Wrap;
            detail.Tag="notification.policy.failure"; detail.Margin=new Thickness(0,4,0,6); Children.Add(detail);
            var retry=Ui.Button(copy.Text("Retry loading settings","重试加载配置","重試載入設定"),()=> { owner.Notifications.RetryPolicy(); Build(); });
            retry.Tag="notification.policy.retry"; retry.Margin=new Thickness(0,0,0,12); Children.Add(retry);
        }
        var matrix=new NotificationMatrixSettingsView(owner) { IsEnabled=owner.Notifications.PolicyActive&&!owner.Notifications.PolicyLoadFailed };
        Children.Add(matrix); SettingsVisual.ApplyButtons(this,dark);
    }
}
