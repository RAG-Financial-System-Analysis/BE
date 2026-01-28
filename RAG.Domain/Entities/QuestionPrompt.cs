using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Question_Prompt")]
public partial class QuestionPrompt
{
    [Key]
    public Guid Id { get; set; }

    public Guid SessionId { get; set; }

    public string QuestionText { get; set; } = null!;

    public string? ResponseText { get; set; }

    [Column(TypeName = "timestamp without time zone")]
    public DateTime? CreatedAt { get; set; }

    [ForeignKey("SessionId")]
    [InverseProperty("QuestionPrompts")]
    public virtual ChatSession Session { get; set; } = null!;

    [ForeignKey("PromptId")]
    [InverseProperty("Prompts")]
    public virtual ICollection<AnalyticsReport> Analytics { get; set; } = new List<AnalyticsReport>();

    [ForeignKey("PromptId")]
    [InverseProperty("Prompts")]
    public virtual ICollection<RatioValue> RatioValues { get; set; } = new List<RatioValue>();
}
