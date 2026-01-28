using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Chat_Sessions")]
public partial class ChatSession
{
    [Key]
    public Guid Id { get; set; }

    public Guid UserId { get; set; }

    public string? Title { get; set; }

    [Column(TypeName = "timestamp without time zone")]
    public DateTime? StartTime { get; set; }

    [InverseProperty("Session")]
    public virtual ICollection<QuestionPrompt> QuestionPrompts { get; set; } = new List<QuestionPrompt>();

    [ForeignKey("UserId")]
    [InverseProperty("ChatSessions")]
    public virtual User User { get; set; } = null!;
}
