using System;

namespace RAG.Domain.DTOs.Analytic
{
    public class GenerateAnalyticsReportResponse
    {
        public Guid ReportId { get; set; }
        public string Message { get; set; } = string.Empty;
        public string FileUrl { get; set; } = string.Empty;
    }
}
