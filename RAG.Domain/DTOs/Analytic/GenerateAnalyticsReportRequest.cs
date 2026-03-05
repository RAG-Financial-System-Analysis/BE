using System;

namespace RAG.Domain.DTOs.Analytic
{
    public class GenerateAnalyticsReportRequest
    {
        public Guid SessionId { get; set; }
        public Guid ReportFinancialId { get; set; }
        public string Title { get; set; } = string.Empty;
    }
}
