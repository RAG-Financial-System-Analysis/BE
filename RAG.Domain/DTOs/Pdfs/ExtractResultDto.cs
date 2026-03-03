using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Pdfs
{
    public class ExtractResultDto
    {
        public string Text { get; set; } = string.Empty;
        public List<MetricDto> Metrics { get; set; } = new();
        public int PageCount { get; set; }
        public long FileSizeBytes { get; set; }
    }
}
