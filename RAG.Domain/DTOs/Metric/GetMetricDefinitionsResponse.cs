using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Metric
{
    public class MetricDefinitionDto
    {
        public Guid Id { get; set; }
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Formula { get; set; } = string.Empty;
        public string Unit { get; set; } = string.Empty;
        public string GroupName { get; set; } = string.Empty;
    }

    public class GetMetricDefinitionsResponse
    {
        public List<MetricDefinitionDto> Definitions { get; set; } = new();
    }
}
