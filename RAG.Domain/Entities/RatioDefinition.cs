using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Ratio_Definition")]
public partial class RatioDefinition
{
    [Key]
    public Guid Id { get; set; }

    public Guid GroupId { get; set; }

    public string Name { get; set; } = null!;

    public string? Formula { get; set; }

    public string? Description { get; set; }

    public Guid? ParentId { get; set; }

    [ForeignKey("GroupId")]
    [InverseProperty("RatioDefinitions")]
    public virtual RatioGroup Group { get; set; } = null!;

    [InverseProperty("Parent")]
    public virtual ICollection<RatioDefinition> InverseParent { get; set; } = new List<RatioDefinition>();

    [ForeignKey("ParentId")]
    [InverseProperty("InverseParent")]
    public virtual RatioDefinition? Parent { get; set; }

    [InverseProperty("Definition")]
    public virtual ICollection<RatioValue> RatioValues { get; set; } = new List<RatioValue>();
}
