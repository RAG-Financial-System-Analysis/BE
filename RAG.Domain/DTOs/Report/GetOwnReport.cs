using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Report
{
    public class GetOwnReport<T>
    {
        public int Total { get; set; }
        public int Page { get; set; }

        public int PageSize { get; set; }

        public List<T> Data { get; set; } = new List<T>();
    }

    public class MyReportItemDto
    {
        public Guid Id { get; set; }
        public string? CompanyName { get; set; }
        public string? Ticker { get; set; }
        public string? CategoryName { get; set; }
        public int Year { get; set; }
        public string? Period { get; set; }
        public string? Visibility { get; set; }
        public string? FileName { get; set; }
        public int? FileSizeKb { get; set; }
        public DateTime? CreatedAt { get; set; }
    }
}
