using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Metric
{
    public class CalculateMetricsRequest
    {
        public Guid ReportId { get; set; }
        public List<string> MetricCodes { get; set; } = new();
    }

    public class CalculatedMetricDto
    {
        public string Code { get; set; } = string.Empty;
        public decimal Value { get; set; }
        public string Unit { get; set; } = string.Empty;
    }

    public class CalculateMetricsResponse
    {
        public Guid ReportId { get; set; }
        public List<CalculatedMetricDto> Calculated { get; set; } = new();
        public List<string> Failed { get; set; } = new();
    }
}
