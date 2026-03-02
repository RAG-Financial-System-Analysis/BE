using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class Company
{
    public Guid Id { get; set; }

    public string Ticker { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? Industry { get; set; }

    public string? Description { get; set; }

    public string? Website { get; set; }

    public DateTime? Createdat { get; set; }

    public DateTime? Updatedat { get; set; }

    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();
}
