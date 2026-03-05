using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Analytic
{
    public class AnalyticsReportItemDto
    {
        public Guid Id { get; set; }
        public string Title { get; set; } = string.Empty;
        public Guid SessionId { get; set; }
        public string FileUrl { get; set; } = string.Empty;
        public string GenerationType { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class GetAnalyticsReportsResponse
    {
        public int Total { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public List<AnalyticsReportItemDto> Data { get; set; } = new();
    }
}
