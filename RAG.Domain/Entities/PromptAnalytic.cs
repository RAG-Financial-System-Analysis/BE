using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class PromptAnalytic
{
    public Guid Promptid { get; set; }

    public Guid Analyticsid { get; set; }

    public decimal? Relevancescore { get; set; }

    public virtual AnalyticsReport Analytics { get; set; } = null!;

    public virtual QuestionPrompt Prompt { get; set; } = null!;
}
