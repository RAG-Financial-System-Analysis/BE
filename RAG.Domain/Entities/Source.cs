using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

public partial class Source
{
    [Key]
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    public string? Url { get; set; }

    public string? Type { get; set; }

    [InverseProperty("Source")]
    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();

    [ForeignKey("SourceId")]
    [InverseProperty("Sources")]
    public virtual ICollection<Regulation> Regulations { get; set; } = new List<Regulation>();
}
