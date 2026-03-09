using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Admin
{
    public class GetReportCategoriesResponse
    {
        public int Total { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public List<ReportCategoryDto> Data { get; set; } = new List<ReportCategoryDto>();
    }

    public class ReportCategoryDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string? Description { get; set; }
        public int AssociatedReportsCount { get; set; }
    }
}
