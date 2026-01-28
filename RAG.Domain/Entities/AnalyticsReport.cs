using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Analytics_Report")]
public partial class AnalyticsReport
{
    [Key]
    public Guid Id { get; set; }

    public Guid? ReportFinancialId { get; set; }

    public string? Title { get; set; }

    public string? GeneratedContent { get; set; }

    [Column(TypeName = "timestamp without time zone")]
    public DateTime? CreatedAt { get; set; }

    [ForeignKey("ReportFinancialId")]
    [InverseProperty("AnalyticsReports")]
    public virtual ReportFinancial? ReportFinancial { get; set; }

    [ForeignKey("AnalyticsId")]
    [InverseProperty("Analytics")]
    public virtual ICollection<QuestionPrompt> Prompts { get; set; } = new List<QuestionPrompt>();
}
