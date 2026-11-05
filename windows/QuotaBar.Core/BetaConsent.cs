namespace QuotaBar.Core;
public sealed class BetaConsent {
    readonly UpdateChannelStore store;
    volatile bool effective;
    public bool Persisted { get; private set; }
    public bool Effective=>effective;
    public BetaConsent(UpdateChannelStore store) { this.store=store;Persisted=store.Load();effective=Persisted; }
    public bool Enable(Func<int,bool> confirm) {
        if(Persisted) return Effective;
        if(!confirm(1) || !confirm(2)) return false;
        store.Save(true); Persisted=true; effective=true; return true;
    }
    public void Suspend()=>effective=false;
    public void FinishDisable() { store.Save(false);Persisted=false;effective=false; }
}
