using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class PromptRatiovalue
{
    public Guid Promptid { get; set; }

    public Guid Ratiovalueid { get; set; }

    public decimal? Relevancescore { get; set; }

    public virtual QuestionPrompt Prompt { get; set; } = null!;

    public virtual RatioValue Ratiovalue { get; set; } = null!;
}
