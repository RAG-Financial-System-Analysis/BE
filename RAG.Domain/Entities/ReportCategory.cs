using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class ReportCategory
{
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    public string? Description { get; set; }

    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();
}
