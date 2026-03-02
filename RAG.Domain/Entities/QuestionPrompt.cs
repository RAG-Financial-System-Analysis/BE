using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class QuestionPrompt
{
    public Guid Id { get; set; }

    public Guid Sessionid { get; set; }

    public string Questiontext { get; set; } = null!;

    public string? Responsetext { get; set; }

    public int? Retrievalcount { get; set; }

    public string? Generationmodel { get; set; }

    public DateTime? Createdat { get; set; }

    public virtual ICollection<PromptAnalytic> PromptAnalytics { get; set; } = new List<PromptAnalytic>();

    public virtual ICollection<PromptRatiovalue> PromptRatiovalues { get; set; } = new List<PromptRatiovalue>();

    public virtual ChatSession Session { get; set; } = null!;
}
