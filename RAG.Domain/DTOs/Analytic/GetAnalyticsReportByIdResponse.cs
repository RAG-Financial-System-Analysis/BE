using System;

namespace RAG.Domain.DTOs.Analytic
{
    public class GeneratedByDto
    {
        public Guid Id { get; set; }
        public string FullName { get; set; } = string.Empty;
    }

    public class GetAnalyticsReportByIdResponse
    {
        public Guid Id { get; set; }
        public string Title { get; set; } = string.Empty;
        public Guid SessionId { get; set; }
        public Guid ReportFinancialId { get; set; }
        public string GeneratedContent { get; set; } = string.Empty;
        public string FileUrl { get; set; } = string.Empty;
        public string GenerationType { get; set; } = string.Empty;
        public GeneratedByDto? GeneratedBy { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
