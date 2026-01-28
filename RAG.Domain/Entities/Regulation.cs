using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Regulation")]
public partial class Regulation
{
    [Key]
    public Guid Id { get; set; }

    public string Code { get; set; } = null!;

    public string Name { get; set; } = null!;

    public string? Description { get; set; }

    [ForeignKey("RegulationId")]
    [InverseProperty("Regulations")]
    public virtual ICollection<Source> Sources { get; set; } = new List<Source>();
}
