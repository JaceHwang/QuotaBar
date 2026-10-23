namespace QuotaBar.Core;
public readonly record struct BubbleRect(double X,double Y,double Width,double Height);
public static class NotificationBubbleLayout {
    public static BubbleRect? Place(BubbleRect anchor,BubbleRect work,double width,double height) {
        if(width<=0||height<=0||width>work.Width-16||height>work.Height-16) return null;
        var x=Math.Clamp(anchor.X,work.X+8,work.X+work.Width-8-width);
        var above=anchor.Y-8-height; var below=anchor.Y+anchor.Height+8;
        if(above>=work.Y+8) return new(x,above,width,height);
        if(below+height<=work.Y+work.Height-8) return new(x,below,width,height);
        return null;
    }
}
