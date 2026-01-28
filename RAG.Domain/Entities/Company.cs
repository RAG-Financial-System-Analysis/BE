using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Company")]
public partial class Company
{
    [Key]
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    public string? Ticker { get; set; }

    public string? Industry { get; set; }

    public string? Description { get; set; }

    [InverseProperty("Company")]
    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();
}
