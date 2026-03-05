using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.OpenAI
{
    public class RagResponseDto
    {
        public Guid PromptId { get; set; }
        public string ResponseText { get; set; } = string.Empty;
        public List<CitationDto> Citations { get; set; } = new();
        public int RetrievalCount { get; set; }
    }
}
