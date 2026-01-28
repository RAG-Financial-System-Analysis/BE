using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using Microsoft.EntityFrameworkCore;

namespace RAG.Infrastructure;

[Table("Users")]
[Index("Email", Name = "Users_Email_key", IsUnique = true)]
public partial class User
{
    [Key]
    public Guid Id { get; set; }

    public Guid RoleId { get; set; }

    public string CognitoSub { get; set; } = null!;

    public string Email { get; set; } = null!;

    public string? FullName { get; set; }

    [Column(TypeName = "timestamp without time zone")]
    public DateTime? CreatedAt { get; set; }

    [InverseProperty("User")]
    public virtual ICollection<ChatSession> ChatSessions { get; set; } = new List<ChatSession>();

    public virtual Role Role { get; set; } = null!;
}
