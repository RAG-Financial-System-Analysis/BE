using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Ratio_Group")]
public partial class RatioGroup
{
    [Key]
    public Guid Id { get; set; }

    public string Name { get; set; } = null!;

    [InverseProperty("Group")]
    public virtual ICollection<RatioDefinition> RatioDefinitions { get; set; } = new List<RatioDefinition>();
}
