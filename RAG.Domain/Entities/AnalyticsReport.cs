using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class AnalyticsReport
{
    public Guid Id { get; set; }

    public Guid? Sessionid { get; set; }

    public Guid? Reportfinancialid { get; set; }

    public string? Title { get; set; }

    public string? Generatedcontent { get; set; }

    public string? Fileurl { get; set; }

    public string? Generationtype { get; set; }

    public Guid? Generatedby { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual User? GeneratedbyNavigation { get; set; }

    public virtual ICollection<PromptAnalytic> PromptAnalytics { get; set; } = new List<PromptAnalytic>();

    public virtual ReportFinancial? Reportfinancial { get; set; }

    public virtual ChatSession? Session { get; set; }
}
