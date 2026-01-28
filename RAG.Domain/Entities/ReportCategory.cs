using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Report_Category")]
public partial class ReportCategory
{
    [Key]
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    [InverseProperty("Category")]
    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();
}
