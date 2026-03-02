using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class RatioGroup
{
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    public string? Description { get; set; }

    public virtual ICollection<RatioDefinition> RatioDefinitions { get; set; } = new List<RatioDefinition>();
}
