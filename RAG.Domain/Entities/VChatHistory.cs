using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class VChatHistory
{
    public Guid? Messageid { get; set; }

    public Guid? Sessionid { get; set; }

    public string? Questiontext { get; set; }

    public string? Responsetext { get; set; }

    public DateTime? Createdat { get; set; }

    public Guid? Userid { get; set; }

    public Guid? Analyticstypeid { get; set; }

    public string? Username { get; set; }

    public string? Analyticstypename { get; set; }

    public string? Analyticstypecode { get; set; }

    public long? Citationcount { get; set; }

    public long? Analyticsreportcount { get; set; }
}
