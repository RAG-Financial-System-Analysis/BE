using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class AuditLog
{
    public Guid Id { get; set; }

    public Guid? Userid { get; set; }

    public string Action { get; set; } = null!;

    public string? Resourcetype { get; set; }

    public Guid? Resourceid { get; set; }

    public string? Details { get; set; }

    public string? Ipaddress { get; set; }

    public string? Useragent { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual User? User { get; set; }
}
