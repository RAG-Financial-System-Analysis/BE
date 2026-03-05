using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.OpenAI
{
    public class CitationDto
    {
        public Guid ReportId { get; set; }
        public string Source { get; set; } = string.Empty;
    }
}
