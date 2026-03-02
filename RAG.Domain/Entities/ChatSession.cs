using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class ChatSession
{
    public Guid Id { get; set; }

    public Guid Userid { get; set; }

    public Guid? Analyticstypeid { get; set; }

    public string? Title { get; set; }

    public DateTime? Starttime { get; set; }

    public DateTime? Lastmessageat { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual ICollection<AnalyticsReport> AnalyticsReports { get; set; } = new List<AnalyticsReport>();

    public virtual AnalyticsType? Analyticstype { get; set; }

    public virtual ICollection<QuestionPrompt> QuestionPrompts { get; set; } = new List<QuestionPrompt>();

    public virtual User User { get; set; } = null!;
}
