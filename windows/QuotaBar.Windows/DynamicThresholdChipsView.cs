namespace QuotaBar.Windows;
/// Native numeric editors wrap with the category title; an added blank stays unsaved until committed.
internal sealed class DynamicThresholdChipsView : WrapPanel {
 readonly TextBlock title;
 readonly string key,unit;
 readonly int maximum;
 readonly Copy copy;
 readonly bool dark;
 readonly Func<int[]> read;
 readonly Action<int[],IReadOnlyDictionary<int,int>?> save;
 bool rebuilding;
 bool adding;
 Button? addButton;
 public DynamicThresholdChipsView(TextBlock title,string key,int maximum,string unit,Copy copy,bool dark,Func<int[]> read,Action<int[],IReadOnlyDictionary<int,int>?> save) {
  this.title=title; this.key=key; this.maximum=maximum; this.unit=unit; this.copy=copy; this.dark=dark; this.read=read; this.save=save;
  Tag="notification.threshold."+key; Render();
 }
 void Render() {
  rebuilding=true;
  var desired=new List<UIElement>(); title.Margin=new Thickness(0,0,8,4); desired.Add(title);
  var values=read();
  var previous=Children.OfType<Border>().ToDictionary(b=>b.Tag!.ToString()!);
  TextBox? blank=null;
  foreach(var value in values) {
   var id=value.ToString();
   if(previous.TryGetValue(id,out var chip)) desired.Add(chip);
   else desired.Add(CreateChip(value,out _));
  }
  if(values.Length==0&&!adding) { var hint=Ui.Text(copy.Text("No thresholds","暂无阈值","暫無閾值"),11,SettingsVisual.Muted(dark)); hint.Margin=new Thickness(0,3,6,4); desired.Add(hint); }
  if(adding) {
   if(previous.TryGetValue("new",out var pending)) desired.Add(pending);
   else desired.Add(CreateChip(null,out blank));
  }
  if(addButton is null) {
   addButton=Ui.Button("+",()=> { if(adding||read().Length>=32) return; adding=true; Render(); });
   addButton.Tag="notification.threshold."+key+".add"; addButton.Margin=new Thickness(0,0,0,4);
   System.Windows.Automation.AutomationProperties.SetName(addButton,copy.Text("Add threshold","添加阈值","新增閾值")+" · "+title.Text);
  }
  addButton.IsEnabled=values.Length<32&&!adding; desired.Add(addButton);
  // Retain every unchanged editor and the add action in the visual tree. A blur
  // may be running while WPF is focusing one of those exact control instances.
  foreach(var obsolete in Children.Cast<UIElement>().Where(c=>!desired.Contains(c)).ToArray()) Children.Remove(obsolete);
  for(var i=0;i<desired.Count;i++) {
   var child=desired[i]; if(i<Children.Count&&ReferenceEquals(Children[i],child)) continue;
   if(Children.Contains(child)) Children.Remove(child);
   Children.Insert(i,child);
  }
  SettingsVisual.ApplyButtons(this,dark); rebuilding=false;
  if(blank is {} input) input.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Input,new Action(()=> { if(adding&&input.Parent!=null) { input.Focus(); input.SelectAll(); } }));
 }
 Border CreateChip(int? original,out TextBox editor) {
  var row=new StackPanel { Orientation=Orientation.Horizontal,Margin=new Thickness(0,0,6,4) };
  var input=new TextBox { Text=original?.ToString()??"",Width=maximum>99?40:26,MinHeight=24,Padding=new Thickness(2,1,2,1),VerticalContentAlignment=VerticalAlignment.Center,Background=Ui.Surface(dark),Foreground=Ui.Foreground(dark),Tag="notification.threshold."+key+"."+(original?.ToString()??"new") };
  System.Windows.Automation.AutomationProperties.SetName(input,title.Text+" · "+(original?.ToString()??copy.Text("New threshold","新阈值","新閾值"))+unit);
  input.ToolTip=copy.Text($"Whole number 1–{maximum}; Enter to save, Escape to cancel.",$"1–{maximum} 的整数；回车保存，Esc 取消。",$"1–{maximum} 的整數；Enter 儲存，Esc 取消。");
  var finished=false;
  Button? remove=null;
  void Finish(bool commit) {
   if(rebuilding||finished) return;
   var values=read(); var valid=int.TryParse(input.Text,out var value)&&value>=1&&value<=maximum&&(value==original||!values.Contains(value))&&(original.HasValue||values.Length<32);
   if(original.HasValue&&(!commit||!valid||value==original)) {
    input.Text=original.Value.ToString(); return;
   }
   finished=true; adding=false;
   if(commit&&valid&&value!=original) {
    var next=values.Where(v=>v!=original).Append(value).OrderDescending().ToArray();
    save(next,key=="bank"&&original is {} old?new Dictionary<int,int> { [value]=old }:null);
   }
   Render();
   if(original.HasValue&&read().Contains(original.Value)) { input.Text=original.Value.ToString(); finished=false; }
  }
  input.KeyDown+=(_,e)=> { if(e.Key==System.Windows.Input.Key.Enter) { e.Handled=true; Finish(true); } else if(e.Key==System.Windows.Input.Key.Escape) { e.Handled=true; Finish(false); } };
  input.LostKeyboardFocus+=(_,e)=> { if(!ReferenceEquals(e.NewFocus,remove)) Finish(true); };
  row.Children.Add(input);
  var suffix=Ui.Text(unit,11,SettingsVisual.Muted(dark)); suffix.VerticalAlignment=VerticalAlignment.Center; suffix.Margin=new Thickness(2,0,2,0); row.Children.Add(suffix);
  remove=Ui.Button("×",()=> { if(rebuilding) return; finished=true; adding=false; if(original.HasValue) save(read().Where(v=>v!=original.Value).ToArray(),null); Render(); });
  // Keep the editor intact while Tab/click moves to its own delete action.
  // Treat editor and delete as one focus region; commit only when leaving it.
  remove.LostKeyboardFocus+=(_,e)=> { if(!ReferenceEquals(e.NewFocus,input)) Finish(true); };
  remove.Tag="notification.threshold."+key+".remove."+(original?.ToString()??"new");
  System.Windows.Automation.AutomationProperties.SetName(remove,copy.Text("Remove threshold","删除阈值","刪除閾值")+" · "+(original?.ToString()??copy.Text("New","新增","新增"))+unit);
  row.Children.Add(remove); editor=input; return new Border { Child=row,Tag=original?.ToString()??"new",CornerRadius=new CornerRadius(5) };
 }
}
