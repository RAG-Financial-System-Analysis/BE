using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class User
{
    public Guid Id { get; set; }

    public Guid Roleid { get; set; }

    public string? Cognitosub { get; set; }

    public string Email { get; set; } = null!;

    public string? Passwordhash { get; set; }

    public string? Fullname { get; set; }

    public bool? Isactive { get; set; }

    public DateTime? Createdat { get; set; }

    public DateTime? Lastloginat { get; set; }

    public virtual ICollection<AnalyticsReport> AnalyticsReports { get; set; } = new List<AnalyticsReport>();

    public virtual ICollection<AuditLog> AuditLogs { get; set; } = new List<AuditLog>();

    public virtual ICollection<ChatSession> ChatSessions { get; set; } = new List<ChatSession>();

    public virtual ICollection<ReportFinancial> ReportFinancials { get; set; } = new List<ReportFinancial>();

    public virtual Role Role { get; set; } = null!;
}
