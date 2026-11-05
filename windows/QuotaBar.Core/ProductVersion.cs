using System.Globalization;
using System.Text.RegularExpressions;

namespace QuotaBar.Core;

/// <summary>Restricted version identity for stable and beta product updates.</summary>
public sealed record ProductVersion(int Major,int Minor,int Patch,int? Beta) : IComparable<ProductVersion> {
    public bool IsBeta=>Beta is not null;
    public string NumericVersion=>$"{Major}.{Minor}.{Patch}";
    public static ProductVersion Parse(string value) {
        if(value is null || value.Length>128) throw new FormatException("Invalid product version");
        var match=Regex.Match(value,@"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.([1-9][0-9]*))?\z",RegexOptions.CultureInvariant);
        if(!match.Success) throw new FormatException("Invalid product version");
        static int Number(string text,int max) {
            if(!int.TryParse(text,NumberStyles.None,CultureInfo.InvariantCulture,out var n) || n>max) throw new FormatException("Invalid product version");
            return n;
        }
        return new(Number(match.Groups[1].Value,65534),Number(match.Groups[2].Value,65534),Number(match.Groups[3].Value,65534),match.Groups[4].Success?Number(match.Groups[4].Value,int.MaxValue):null);
    }
    public int CompareTo(ProductVersion? other) {
        if(other is null) return 1;
        var n=Major.CompareTo(other.Major); if(n!=0) return n;
        n=Minor.CompareTo(other.Minor); if(n!=0) return n;
        n=Patch.CompareTo(other.Patch); if(n!=0) return n;
        if(Beta is null) return other.Beta is null?0:1;
        return other.Beta is null?-1:Beta.Value.CompareTo(other.Beta.Value);
    }
}
