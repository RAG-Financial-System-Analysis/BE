using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class RatioDefinition
{
    public Guid Id { get; set; }

    public Guid Groupid { get; set; }

    public Guid? Parentid { get; set; }

    public string Code { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? Formula { get; set; }

    public string? Description { get; set; }

    public string? Unit { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual RatioGroup Group { get; set; } = null!;

    public virtual ICollection<RatioDefinition> InverseParent { get; set; } = new List<RatioDefinition>();

    public virtual RatioDefinition? Parent { get; set; }

    public virtual ICollection<RatioValue> RatioValues { get; set; } = new List<RatioValue>();
}
