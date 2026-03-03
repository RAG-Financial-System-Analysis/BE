using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Report
{
    public class ReportDetailDto
    {
        public Guid Id { get; set; }
        public CompanyBriefDto Company { get; set; } = new();
        public string? CategoryName { get; set; }
        public int Year { get; set; }
        public string? Period { get; set; }
        public string? FileUrl { get; set; }
        public string? FileName { get; set; }
        public int? FileSizeKb { get; set; }
        public string? Visibility { get; set; }
        public UserBriefDto UploadedBy { get; set; } = new();
        public DateTime? CreatedAt { get; set; }
        public List<MetricResponse>? Metrics { get; set; }
    }

    public class CompanyBriefDto
    {
        public Guid Id { get; set; }
        public string? Ticker { get; set; }
        public string? Name { get; set; }
    }

    public class UserBriefDto
    {
        public Guid Id { get; set; }
        public string? FullName { get; set; }
    }
}
