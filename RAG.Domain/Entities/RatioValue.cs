using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class RatioValue
{
    public Guid Id { get; set; }

    public Guid Reportid { get; set; }

    public Guid Definitionid { get; set; }

    public decimal? Value { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual RatioDefinition Definition { get; set; } = null!;

    public virtual ICollection<PromptRatiovalue> PromptRatiovalues { get; set; } = new List<PromptRatiovalue>();

    public virtual ReportFinancial Report { get; set; } = null!;
}
