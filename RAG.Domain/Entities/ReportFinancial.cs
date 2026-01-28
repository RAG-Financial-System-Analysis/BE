using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Report_Financial")]
public partial class ReportFinancial
{
    [Key]
    public Guid Id { get; set; }

    public Guid CompanyId { get; set; }

    public Guid CategoryId { get; set; }

    public Guid? SourceId { get; set; }

    public int Year { get; set; }

    public string? Period { get; set; }

    public string? FileUrl { get; set; }

    public string? ContentRaw { get; set; }

    [InverseProperty("ReportFinancial")]
    public virtual ICollection<AnalyticsReport> AnalyticsReports { get; set; } = new List<AnalyticsReport>();

    [ForeignKey("CategoryId")]
    [InverseProperty("ReportFinancials")]
    public virtual ReportCategory Category { get; set; } = null!;

    [ForeignKey("CompanyId")]
    [InverseProperty("ReportFinancials")]
    public virtual Company Company { get; set; } = null!;

    [InverseProperty("Report")]
    public virtual ICollection<RatioValue> RatioValues { get; set; } = new List<RatioValue>();

    [ForeignKey("SourceId")]
    [InverseProperty("ReportFinancials")]
    public virtual Source? Source { get; set; }
}
