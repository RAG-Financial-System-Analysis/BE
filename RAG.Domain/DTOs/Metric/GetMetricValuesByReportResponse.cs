using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Metric
{
    public class MetricDefinitionShortDto
    {
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
    }

    public class MetricValueDto
    {
        public Guid Id { get; set; }
        public MetricDefinitionShortDto Definition { get; set; } = new();
        public decimal Value { get; set; }
        public string Unit { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class GetMetricValuesByReportResponse
    {
        public Guid ReportId { get; set; }
        public List<MetricValueDto> Values { get; set; } = new();
    }
}
