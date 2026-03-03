using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Report
{
    public class ReportMetricsDto
    {
        public Guid ReportId { get; set; }
        public List<MetricDetailDto> Metrics { get; set; } = new();
    }

    public class MetricDetailDto
    {
        public Guid Id { get; set; }
        public string? Code { get; set; }
        public string? Name { get; set; }
        public decimal Value { get; set; }
        public string? Unit { get; set; }
        public string? GroupName { get; set; }
    }

}
