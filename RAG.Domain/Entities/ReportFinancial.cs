using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class ReportFinancial
{
    public Guid Id { get; set; }

    public Guid Companyid { get; set; }

    public Guid Categoryid { get; set; }

    public Guid Uploadedby { get; set; }

    public int Year { get; set; }

    public string? Period { get; set; }

    public string Fileurl { get; set; } = null!;

    public string? Filename { get; set; }

    public int? Filesizekb { get; set; }

    public string? Contentraw { get; set; }

    public string? Visibility { get; set; }

    public DateTime? Createdat { get; set; }

    public DateTime? Updatedat { get; set; }

    public virtual ICollection<AnalyticsReport> AnalyticsReports { get; set; } = new List<AnalyticsReport>();

    public virtual ReportCategory Category { get; set; } = null!;

    public virtual Company Company { get; set; } = null!;

    public virtual ICollection<RatioValue> RatioValues { get; set; } = new List<RatioValue>();

    public virtual User UploadedbyNavigation { get; set; } = null!;
}
