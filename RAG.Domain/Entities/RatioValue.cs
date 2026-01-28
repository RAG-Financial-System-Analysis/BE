using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Ratio_Value")]
public partial class RatioValue
{
    [Key]
    public Guid Id { get; set; }

    public Guid ReportId { get; set; }

    public Guid DefinitionId { get; set; }

    [Precision(18, 4)]
    public decimal? Value { get; set; }

    [ForeignKey("DefinitionId")]
    [InverseProperty("RatioValues")]
    public virtual RatioDefinition Definition { get; set; } = null!;

    [ForeignKey("ReportId")]
    [InverseProperty("RatioValues")]
    public virtual ReportFinancial Report { get; set; } = null!;

    [ForeignKey("RatioValueId")]
    [InverseProperty("RatioValues")]
    public virtual ICollection<QuestionPrompt> Prompts { get; set; } = new List<QuestionPrompt>();
}
