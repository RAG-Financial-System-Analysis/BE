using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Pdfs
{
    public class MetricDto
    {
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public decimal Value { get; set; }
        public string? Unit { get; set; }
    }
}
